// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface PriceOracle {
    function getLatestPrice() external view returns (int256);
    function DollarLimit(uint256 maxinput) external view returns (uint256);
}

contract Article is ReentrancyGuard, Ownable {

    function fundGelatoExecutor() external payable onlyOwner {
        require(executor != address(0), "Executor not set");
    
        payable(executor).transfer(msg.value);
    }

    function setExecutor(address _executor) external {
        require(msg.sender == owner, "Only owner can set executor");
        executor = _executor;
    }

    uint256 public currentMaxUSD = 20;
    uint256 public currentCriticalFee = 5; // 4.20 USD in wei
    PriceOracle public oracle;

    constructor(address oracleAddress) {
        oracle = PriceOracle(oracleAddress);
    }

    function getOraclePrice(uint256 quantity) public view returns (uint256) {
        return oracle.DollarLimit(quantity);
    }

    address public feeCollector;

    function setFeeCollector(address _feeCollector) external onlyOwner {
        feeCollector = _feeCollector;
    }

    struct ArticleResult {
        uint256 startTime;
        uint256 votingPeriod;
        bool liked;
        bool disliked;
        uint256 fraudFlags;
        uint256 lazyFlags;
    }

    mapping(bytes32 => ArticleResult) public articleResult; // User Stakes

    struct StakingEth {
        uint256 stake; // Amount of ETH Staked
        uint256 ratioAtPurchaseTime; // Amount of ETH Staked
    }

    struct ArticleCritic {
        address criticAddress; // User Who Makes Claim
        string quote; // Two Sentences Maximum
        bool lazyFlagged; // Quoted For Bad Research
        bool fraudFlagged; // Quoted For Direct Lie
        uint256 supportEth; // Amount of ETH Supporter is willing to stake
        uint256 denierEth; // Amount of ETH Denier is willing to stake
        mapping(address => StakingEth) stakesUp; // User Stakes Up
        mapping(address => StakingEth) stakesDown; // User Stakes Down
        string[] voters;
    }

    struct ArticleInProcess {
        address author; // Author of the Article
        uint256 startTime; // Start Time of Voting
        uint256 votingPeriod; // Voting Period in Seconds
        bool votingActive; // Voting Active Flag
        uint256 inflateStake; // Total ETH Staked
        uint256 purgeStake; // Total ETH Staked
        uint256 totalCriticals;
        uint256 totalCritics; // Total Critics
        ArticleCritic[] articleCritics;
        mapping(address => StakingEth) stakesUp; // User Stakes Up
        mapping(address => StakingEth) stakesDown; // User Stakes Down
        string[] voters;
    }

    mapping(address => uint256) public pendingWithdrawals;

    function withdraw() public nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds to withdraw.");
        pendingWithdrawals[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }
   

    mapping(bytes32 => ArticleInProcess) public articleValues; // User Stakes
    bytes32[] public activeArticleHashes;

    
    event ArticleCreated(address indexed articleHash, uint256 startTime, uint256 votingPeriod);
    event ArticleFunded(address indexed articleHash, bool liked);
    event ArticleCritical(uint256 index, address criticAddress, string quote, bool lazyFlagged, bool fraudFlagged);
    event CriticalFunded(address indexed articleHash, uint256 criticalIndex, bool liked);
    event ArticleFinalized(address indexed articleHash, bool liked, uint256 fraudFlags, uint256 lazyFlags, uint256 endTime);

    function createTimePeriod(bytes32 articleHash) private {
        articleValues[articleHash].startTime = block.timestamp;
        articleValues[articleHash].votingPeriod = 5 days; // 5 day voting period
    }

    function isExpired(bytes32 articleHash) public view returns (bool) {
        return block.timestamp > articleValues[articleHash].startTime + articleValues[articleHash].votingPeriod;
    }

    function createArticleHash(string memory title, string memory content, address author) public returns (bytes32) {
        bytes32 articleHash = keccak256(abi.encodePacked(title, content, author));
        if (articleValues[articleHash].votingActive) {
            revert("This article already exists.");
        }
        createTimePeriod(articleHash);
        articleValues[articleHash].votingActive = true;
        articleValues[articleHash].author = author;
        activeArticleHashes.push(articleHash);
        return articleHash;
    }

    function criticize(bytes32 articleHash, string memory quote, bool lazyFlagged, bool fraudFlagged) public payable {

        address criticAddress = msg.sender;

        ArticleCritic memory critical;

        uint256 fiveDollarLimit = getOraclePrice(currentCriticalFee);

        require(msg.value > fiveDollarLimit, "Must send 5 worth of Eth to criticize.");

        critical.criticAddress = criticAddress;

        uint256 feeAmount = msg.value / 10; // 10%
        uint256 remainingStake = msg.value - feeAmount;

        if (feeCollector != address(0)) {
            (bool sent, ) = payable(feeCollector).call{value: feeAmount}("");
            require(sent, "Fee transfer failed");
        }

        if (fraudFlagged) {
            critical.fraudFlagged = true;
        } else if (lazyFlagged) {
            critical.lazyFlagged = true;
        } else {
            revert("No input on article.");
        }
        critical.quote = quote;

        articleValues[articleHash].articleCritics.push(critical);

        articleValues[articleHash].totalCritics += 1;

        emit ArticleCritical(articleValues[articleHash].totalCritics - 1, criticAddress, quote, lazyFlagged, fraudFlagged);
    }


    function articleFunded(bytes32 articleHash, bool consensus) public payable {

        require(articleValues[articleHash].votingActive, "Voting is not active for this article.");
        require(msg.value > 0, "Must send ETH to vote.");
        require(msg.sender != articleValues[articleHash].author, "Author cannot vote on their own article.");

        require(articleValues[articleHash].stakesDown[msg.sender].stake == 0 || consensus == true, "You have already voted No on this article.");
        require(articleValues[articleHash].stakesUp[msg.sender].stake == 0 || consensus == false, "You have already voted Yes on this article.");

        ArticleInProcess storage article = articleValues[articleHash];

        uint256 twentyDollarLimit = getOraclePrice(currentMaxUSD);

        uint256 userTotal = article.stakesUp[msg.sender].stake + article.stakesDown[msg.sender].stake + msg.value;

        if (userTotal > twentyDollarLimit) {
            revert("You have exceeded the $20 limit.");
        }

        uint256 ratioAtPurchaseTime; 
        if (consensus) {
            article.stakesUp[msg.sender].stake += msg.value;
            article.inflateStake += msg.value;
            ratioAtPurchaseTime = article.inflateStake * 1000 / (article.inflateStake + article.purgeStake);
        } else {
            article.stakesDown[msg.sender].stake += msg.value;
            article.purgeStake += msg.value;
            ratioAtPurchaseTime = article.purgeStake * 1000 / (article.inflateStake + article.purgeStake);
        }

        article.stakesUp[msg.sender].ratioAtPurchaseTime = ratioAtPurchaseTime;

        article.voters.push(msg.sender);

        emit ArticleFunded(articleHash, consensus);
    }

    function criticalFunded(bytes32 articleHash, uint256 criticalIndex, bool liked, bool fraud, bool lazy) public payable{
        require(articleValues[articleHash].votingActive, "Voting is not active for this article.");
        require(msg.value > 0, "Must send ETH to vote.");
        require(msg.sender != articleValues[articleHash].author, "Author cannot vote on their own article.");

        ArticleInProcess storage article = articleValues[articleHash];
        ArticleCritic storage critic = article.articleCritics[criticalIndex];

        uint256 twentyDollarLimit = getOraclePrice(currentMaxUSD);
        uint256 userTotal = critic.stakesUp[msg.sender].stake + critic.stakesDown[msg.sender].stake + msg.value;
        require(userTotal <= twentyDollarLimit, "You have exceeded the $20 limit.");

        if (liked) {
            critic.supportEth += msg.value;
            critic.stakesUp[msg.sender].stake += msg.value;
            critic.stakesUp[msg.sender].ratioAtPurchaseTime = critic.supportEth * 1000 / (critic.supportEth + critic.denierEth);
        } else {
            critic.denierEth += msg.value;
            critic.stakesDown[msg.sender].stake += msg.value;
            critic.stakesDown[msg.sender].ratioAtPurchaseTime = critic.denierEth * 1000 / (critic.supportEth + critic.denierEth);
        }

        critic.voters.push(msg.sender);
        
        emit CriticalFunded(articleHash, criticalIndex, liked);
    }

    function payOutStakes(bytes32 articleHash) internal {
        ArticleInProcess storage article = articleValues[articleHash];
        bool outcome = article.inflateStake > article.purgeStake;

        for (uint256 iv = 0; iv < article.voters.length; iv++) {
            address voter = article.voters[iv];
            uint256 amount;
            if (outcome) {
                amount = article.stakesUp[voter].stake*article.stakesUp[voter].ratioAtPurchaseTime / 1000; 
            } else if (!outcome) {
                amount = article.stakesDown[voter].stake*article.stakesDown[voter].ratioAtPurchaseTime / 1000;
            }
            pendingWithdrawals[voter] += amount;
        }
    }

    function payOutCriticals (bytes32 articleHash) {
            ArticleInProcess storage article = articleValues[articleHash];
            for (uint256 iv = 0; iv < article.articleCritics.length; iv++) {
                ArticleCritic storage critic = article.articleCritics[iv];
                bool isFraud = critic.fraudFlagged;
                bool isLazy = critic.lazyFlagged;

                if (!isFraud && !isLazy) continue;

                for (uint256 i = 0; i < critic.voters.length; i++) {
                    address voter = critic.voters[i];
                    StakingEth storage stake = isFraud ? critic.stakesUp[voter] : critic.stakesDown[voter];
                    uint256 payout = stake.stake * stake.ratioAtPurchaseTime / 1000;
                    pendingWithdrawals[voter] += payout;
                }
            }
    }

    

    function finalizeArticle(bytes32 articleHash) public {
        require(articleValues[articleHash].votingActive, "Voting is not active for this article.");
        require(isExpired(articleHash), "Voting period has not ended.");

        articleValues[articleHash].votingActive = false;
        ArticleResult memory result;
        result.startTime = articleValues[articleHash].startTime;
        result.votingPeriod = articleValues[articleHash].votingPeriod;
        uint256 total = articleValues[articleHash].inflateStake + articleValues[articleHash].purgeStake;
        if (total == 0) {
            result.liked = false; // No votes cast
        } else{
            result.liked = ((articleValues[articleHash].inflateStake*100/total) > 75) ? true : false;
            result.disliked = ((articleValues[articleHash].purgeStake*100/total) > 75) ? true : false;
        }
        for (uint256 i = 0; i < article.articleCritics.length; i++) {
            if (article.articleCritics[i].fraudFlagged) result.fraudFlags++;
            if (article.articleCritics[i].lazyFlagged) result.lazyFlags++;
        }

        articleResult[articleHash] = result;

        payOutStakes(articleHash);

        payOutCriticals(articleHash);

        for (uint256 i = 0; i < activeArticleHashes.length; i++) {
            if (activeArticleHashes[i] == articleHash) {
                activeArticleHashes[i] = activeArticleHashes[activeArticleHashes.length - 1];
                activeArticleHashes.pop();
                break;
            }
        }

        delete articleValues[articleHash];

        emit ArticleFinalized(articleHash, result.liked, result.fraudFlags, result.lazyFlags, block.timestamp);
    }

    function getArticleInProcess(bytes32 articleHash) external view returns (address author, uint256 startTime, uint256 votingPeriod, bool votingActive, uint256 inflateStake, uint256 purgeStake, uint256 totalCriticals, uint256 totalCritics) {
        ArticleInProcess memory a = articleValues[articleHash];
        return (a.author, a.startTime, a.votingPeriod, a.votingActive, a.inflateStake, a.purgeStake, a.totalCriticals, a.totalCritics);
    }

    function getArticleResult(bytes32 articleHash) external view returns (uint256 startTime, uint256 votingPeriod, bool liked, bool disliked, uint256 fraudFlags, uint256 lazyFlags) {
        ArticleResult memory a = articleResult[articleHash];
        return (a.startTime, a.votingPeriod, a.liked, a.disliked, a.fraudFlags, a.lazyFlags);
    }

    function getPendingWithdrawals() external view returns (uint256) {
        return pendingWithdrawals[msg.sender];
    }

    event CriticalFeeChanged(uint256 newFee);
    event MaxUSDChanged(uint256 newMax);

    function changeCriticalFee(uint256 newFee) public onlyOwner {
        currentCriticalFee = newFee;
        emit CriticalFeeChanged(newFee);
    }

    function changeMaxUSD(uint256 newMax) public onlyOwner {
        currentMaxUSD = newMax;
        emit MaxUSDChanged(newMax);
    }

    function getAllActiveArticles() external view returns (bytes32[] memory) {
        return activeArticleHashes;
    }

    

    function checker() external view returns (bool canExec, bytes memory execPayload) {
        for (uint256 i = 0; i < activeArticleHashes.length; i++) {
            bytes32 hash = activeArticleHashes[i];
            if (articleValues[hash].votingActive && isExpired(hash)) {
                canExec = true;
                execPayload = abi.encodeWithSelector(this.finalizeArticle.selector, hash);
                return (canExec, execPayload);
            }
        }
        return (false, bytes("No expired article available to finalize."));
    }
}