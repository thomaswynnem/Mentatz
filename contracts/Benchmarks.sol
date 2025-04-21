// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";


contract GlobalJournalistStats is Ownable {
    struct ArticleResult {
        bool liked;
        bool fraudFlagged;
        bool lazyFlagged;
    }

    ArticleResult[] public finalizedArticles;

    uint256 public avgLikeRate;
    uint256 public avgDislikeRate;
    uint256 public avgFraudRate;
    uint256 public avgLazyRate;
    uint256 public avgNotFlaggedRate;

    uint256 public stdLikeRate;
    uint256 public stdDislikeRate;
    uint256 public stdFraudRate;
    uint256 public stdLazyRate;
    uint256 public stdNotFlaggedRate;

    uint256 public numberOfShifts;

    event StatsUpdated(uint256 avgLikeRate, uint256 avgFraudRate, uint256 avgLazyRate, uint256 avgNotFlaggedRate, uint256 stdLikeRate, uint256 stdFraudRate, uint256 stdLazyRate, uint256 stdNotFlaggedRate, uint256 version);

    function submitFinalizedArticle(bool liked, bool fraudFlagged, bool lazyFlagged) external {
        finalizedArticles.push(ArticleResult(liked, fraudFlagged, lazyFlagged));

        if (finalizedArticles.length == 1000) {
            computeGlobalAverages();
        }
    }

    address public owner;
    address public executor;

    modifier onlyGelatoOrOwner() {
        require(msg.sender == owner() || msg.sender == executor, "Not authorized");
        _;
    }


    function setExecutor(address _executor) external onlyOwner(){
        require(msg.sender == owner, "Only owner can set executor");
        executor = _executor;
    }

    function withdraw(address payable to, uint256 amount) external onlyGelatoOrOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        to.transfer(amount);
    }

    function computeGlobalAverages() public onlyGelatoOrOwner  {

        require(finalizedArticles.length == 1000, "Must have 1000 articles to compute averages.");

        uint256 totalLiked = 0;
        uint256 totalFraud = 0;
        uint256 totalLazy = 0;
        uint256 totalNotFlagged = 0;

        uint256[1000] memory likeRates;
        uint256[1000] memory fraudRates;
        uint256[1000] memory lazyRates;
        uint256[1000] memory notFlaggedRates;

        for (uint256 i = 0; i < 1000; i++) {
            ArticleResult memory stats = finalizedArticles[i];

            uint256 like = stats.liked ? 100 : 0;
            uint256 fraud = stats.fraudFlagged ? 100 : 0;
            uint256 lazy = stats.lazyFlagged ? 100 : 0;
            uint256 notFlagged = (!stats.fraudFlagged && !stats.lazyFlagged) ? 100 : 0;

            likeRates[i] = like;
            fraudRates[i] = fraud;
            lazyRates[i] = lazy;
            notFlaggedRates[i] = notFlagged;

            totalLiked += like;
            totalFraud += fraud;
            totalLazy += lazy;
            totalNotFlagged += notFlagged;
        }

        // Update moving averages
        avgLikeRate = (totalLiked + avgLikeRate * numberOfShifts) / (numberOfShifts + 1);
        avgFraudRate = (totalFraud + avgFraudRate * numberOfShifts) / (numberOfShifts + 1);
        avgLazyRate = (totalLazy + avgLazyRate * numberOfShifts) / (numberOfShifts + 1);
        avgNotFlaggedRate = (totalNotFlagged + avgNotFlaggedRate * numberOfShifts) / (numberOfShifts + 1);
        avgDislikeRate = 100 - avgLikeRate;

        // Compute variances
        uint256 varLike = 0;
        uint256 varFraud = 0;
        uint256 varLazy = 0;
        uint256 varNotFlagged = 0;

        for (uint256 i = 0; i < 1000; i++) {
            varLike += (likeRates[i] > avgLikeRate ? (likeRates[i] - avgLikeRate)**2 : (avgLikeRate - likeRates[i])**2);
            varFraud += (fraudRates[i] > avgFraudRate ? (fraudRates[i] - avgFraudRate)**2 : (avgFraudRate - fraudRates[i])**2);
            varLazy += (lazyRates[i] > avgLazyRate ? (lazyRates[i] - avgLazyRate)**2 : (avgLazyRate - lazyRates[i])**2);
            varNotFlagged += (notFlaggedRates[i] > avgNotFlaggedRate ? (notFlaggedRates[i] - avgNotFlaggedRate)**2 : (avgNotFlaggedRate - notFlaggedRates[i])**2);
        }

        // Compute standard deviations
        stdLikeRate = sqrt(varLike / 1000);
        stdFraudRate = sqrt(varFraud / 1000);
        stdLazyRate = sqrt(varLazy / 1000);
        stdNotFlaggedRate = sqrt(varNotFlagged / 1000);
        stdDislikeRate = stdLikeRate;

        numberOfShifts++;
        delete finalizedArticles;

        emit StatsUpdated(avgLikeRate, avgFraudRate, avgLazyRate, avgNotFlaggedRate, stdLikeRate, stdFraudRate, stdLazyRate, stdNotFlaggedRate, numberOfShifts);
    }

    // Integer square root using Babylonian method
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function checker() external view returns (bool canExec, bytes memory execPayload) {
    // Check if the number of finalized articles is 1000
    if (finalizedArticles.length == 1000) {
     // If so, return the function call to computeGlobalAverages
        execPayload = abi.encodeWithSignature("computeGlobalAverages()");
        canExec = true;
     
    } else {
     // Otherwise, return an empty payload and set canExec to false
        execPayload= bytes("Not enough articles yet");
        canExec = false;
    }
    return (canExec, execPayload);
  }
}
