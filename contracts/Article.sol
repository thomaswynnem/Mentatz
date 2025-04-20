// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface PriceOracle {
    function getLatestPrice() external view returns (int256);
    function DollarLimit(uint256 maxinput) external view returns (uint256);
}

contract Article {

    uint256 public currentMaxUSD = 20;
    PriceOracle public oracle;

    constructor(address oracleAddress) {
        oracle = PriceOracle(oracleAddress);
    }

    function getOraclePrice() public view returns (uint256) {
        return oracle.DollarLimit(currentMaxUSD);
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
    }

    struct ArticleInProcess {
        address author; // Author of the Article
        uint256 startTime; // Start Time of Voting
        uint256 votingPeriod; // Voting Period in Seconds
        bool votingActive; // Voting Active Flag
        uint256 consensusStaked; // Total ETH Staked
        uint256 demotionStaked; // Total ETH Staked
        uint256 totalCriticals;
        uint256 totalCritics; // Total Critics
        ArticleCritic[] articleCritics;
        mapping(address => StakingEth) stakesUp; // User Stakes Up
        mapping(address => StakingEth) stakesDown; // User Stakes Down
        string[] voters;
    }

    mapping(bytes32 => ArticleInProcess) public articleValues; // User Stakes

    
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

    function createArticleHash(string memory title, string memory content, address author) public {
        bytes32 articleHash = keccak256(abi.encodePacked(title, content, author));
        if (articleValues[articleHash].votingActive) {
            revert("This article already exists.");
        }
        createTimePeriod(articleHash);
        articleValues[articleHash].votingActive = true;
        articleValues[articleHash].author = author;
        return articleHash;
    }

    function criticize(bytes32 articleHash, string memory quote, bool lazyFlagged, bool fraudFlagged) public {

        address criticAddress = msg.sender;

        ArticleCritic memory critical;

        critical.criticAddress = criticAddress;

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

        require(articleValues[articleHash].stakeUp[msg.sender].stake && consensus == true, "You have already voted yes on this article.");
        require(articleValues[articleHash].stakeDown[msg.sender].stake && consensus == false, "You have already no voted on this article.");

        uint256 twentyDollarLimit = getOraclePrice();

        uint256 userTotal = articleVales[articleHash].stakesUp[msg.sender].stake + articleVales[articleHash].stakesDown[msg.sender].stake + msg.value;

        if (userTotal > twentyDollarLimit) {
            revert("You have exceeded the $20 limit.");
        }

        uint256 ratioAtPurchaseTime; 
        if (consensus) {
            articleValues[articleHash].stakesUp.stake[msg.sender] += msg.value;
            articleValues[articleHash].consensusStaked += msg.value;
            ratioAtPurchaseTime = articleValues[articleHash].consensusStaked * 1000 / (articleValues[articleHash].consensusStaked + articleValues[articleHash].demotionStaked);
        } else {
            articleValues[articleHash].stakesDown.stake[msg.sender] += msg.value;
            articleValues[articleHash].demotionStaked += msg.value;
            ratioAtPurchaseTime = articleValues[articleHash].demotionStaked * 1000 / (articleValues[articleHash].consensusStaked + articleValues[articleHash].demotionStaked);
        }

        articleValues[articleHash].stakesUp[msg.sender].ratioAtPurchaseTime = ratioAtPurchaseTime;

        articleValues[articleHash].voters.push(msg.sender);

        emit ArticleFunded(articleHash, liked);
    }

    function criticalFunded(bytes32 articleHash, uint256 criticalIndex, bool liked, bool fraud, bool lazy) public payable{
        require(articleValues[articleHash].votingActive, "Voting is not active for this article.");
        require(msg.value > 0, "Must send ETH to vote.");
        require(msg.sender != articleValues[articleHash].author, "Author cannot vote on their own article.");

        articleValues[articleHash].stakes[msg.sender] += msg.value;

        uint256 twentyDollarLimit = getOraclePrice();

        if (articleValues[articleHash].stakes[msg.sender] > twentyDollarLimit) {
            revert("You have exceeded the $20 limit.");
        }

        if (liked) {
            articleValues[articleHash].articleCritics[criticalIndex].supportEth += msg.value;
        } else {
            articleValues[articleHash].articleCritics[criticalIndex].denierEth += msg.value;
        }

        emit CriticalFunded(articleHash, criticalIndex, liked);
    }

    function payOutStakes(bytes32 articleHash) internal {

        bool outcome = articleValues[articleHash].consensusStaked > articleValues[articleHash].demotionStaked;

        for (uint256 i = 0; i < articleValues[articleHash].voters.length; i++) {
            address voter = articleValues[articleHash].voters[i];
            if outcome == 1 {
                payable(voter).transfer(articleValues[articleHash].stakesUp[voter].stake*articleValues[articleHash].stakesUp[voter].ratioAtPurchaseTime / 1000); 
            } else if outcome == 0 {
                payable(voter).transfer(articleValues[articleHash].stakesDown[voter].stake*articleValues[articleHash].stakesDown[voter].ratioAtPurchaseTime / 1000);
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
        uint256 total = articleValues[articleHash].likedStaked + articleValues[articleHash].dislikedStaked;
        if (total == 0) {
            result.liked = false; // No votes cast
        } else{
            result.liked = ((articleValues[articleHash].likedStaked*100/total) > 75) ? true : false;
            result.disliked = ((articleValues[articleHash].dislikedStaked*100/total) > 75) ? true : false;
        }

        articleResult[articleHash] = result;

        payOutStakes(articleHash);

        payoutQuotes(articleHash)

        delete articleValues[articleHash];

        emit ArticleFinalized(articleHash, result.liked, result.fraudFlags, result.lazyFlags, block.timestamp);
    }   

    function getArticleResult(bytes32 articleHash) external view returns (uint256 startTime, uint256 votingPeriod, bool liked, bool disliked, uint256 fraudFlags, uint256 lazyFlags) {
        ArticleResult memory a = articleResult[articleHash];
        return (a.startTime, a.votingPeriod, a.liked, a.disliked, a.fraudFlags, a.lazyFlags);
    }
}