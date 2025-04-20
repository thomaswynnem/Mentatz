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

    struct ArticleCritic {
        address criticAddress; // User Who Makes Claim
        string quote; // Two Sentences Maximum
        bool lazyFlagged; // Quoted For Bad Research
        bool fraudFlagged; // Quoted For Direct Lie
        uint256 supportEth; // Amount of ETH Supporter is willing to stake
        uint256 denierEth; // Amount of ETH Denier is willing to stake
    }

    struct ArticleInProcess {
        uint256 startTime; // Start Time of Voting
        uint256 votingPeriod; // Voting Period in Seconds
        bool votingActive; // Voting Active Flag
        uint256 likedStaked; // Total ETH Staked
        uint256 dislikedStaked; // Total ETH Staked
        uint256 totalCriticals;
        uint256 totalCritics; // Total Critics
        ArticleCritic[] articleCritics;
        mapping(address => uint256) stakes; // User Stakes
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

    function articleFunded(bytes32 articleHash, bool liked) public payable {

        require(articleValues[articleHash].votingActive, "Voting is not active for this article.");
        require(msg.value > 0, "Must send ETH to vote.");

        articleValues[articleHash].stakes[msg.sender] += msg.value;

        uint256 twentyDollarLimit = getOraclePrice();

        if (articleValues[articleHash].stakes[msg.sender] > twentyDollarLimit) {
            revert("You have exceeded the $20 limit.");
        }

        if (liked) {
            articleValues[articleHash].likedStaked += msg.value;
        } else {
            articleValues[articleHash].dislikedStaked += msg.value;
        }

        emit ArticleFunded(articleHash, liked);
    }

    function criticalFunded(bytes32 articleHash, uint256 criticalIndex, bool liked, bool fraud, bool lazy) public payable{
        require(articleValues[articleHash].votingActive, "Voting is not active for this article.");
        require(msg.value > 0, "Must send ETH to vote.");

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

        for (uint256 i = 0; i < articleValues[articleHash].totalCritics; i++) {
            if (articleValues[articleHash].articleCritics[i].fraudFlagged && articleValues[articleHash].articleCritics[i].supportEth > articleValues[articleHash].articleCritics[i].denierEth) {
                result.fraudFlags += 1;
            } else if (articleValues[articleHash].articleCritics[i].lazyFlagged && articleValues[articleHash].articleCritics[i].supportEth > articleValues[articleHash].articleCritics[i].denierEth) {
                result.lazyFlags += 1;
            }
        }

        articleResult[articleHash] = result;
        delete articleValues[articleHash];

        emit ArticleFinalized(articleHash, result.liked, result.fraudFlags, result.lazyFlags, block.timestamp);
    }   

    function getArticleResult(bytes32 articleHash) external view returns (uint256 startTime, uint256 votingPeriod, bool liked, bool disliked, uint256 fraudFlags, uint256 lazyFlags) {
        ArticleResult memory a = articleResult[articleHash];
        return (a.startTime, a.votingPeriod, a.liked, a.disliked, a.fraudFlags, a.lazyFlags);
    }
}