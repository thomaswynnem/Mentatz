// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;
 
import "@openzeppelin/contracts@4.7.0/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts@4.7.0/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts@4.7.0/access/Ownable.sol";
import "@openzeppelin/contracts@4.7.0/utils/Counters.sol"; 
 
interface GlobalJournalistStats {
    function avgLikeRate() external view returns (uint256);
    function avgDislikeRate() external view returns (uint256);
    function avgFraudRate() external view returns (uint256);
    function avgLazyRate() external view returns (uint256);
    function avgNotFlaggedRate() external view returns (uint256);

    function stdLikeRate() external view returns (uint256);
    function stdDislikeRate() external view returns (uint256);
    function stdFraudRate() external view returns (uint256);
    function stdLazyRate() external view returns (uint256);
    function stdNotFlaggedRate() external view returns (uint256);
}

interface Article {

    function getArticleResult(bytes32 articleHash) external view returns (
        uint256 startTime,
        uint256 votingPeriod,
        bool liked,
        bool disliked,
        uint256 fraudFlags,
        uint256 lazyFlags
    );
}


contract Mentatz is ERC721, ERC721URIStorage, Ownable {

    enum TagId {
        Amateur,     
        Yellow,      
        Rorschach,   
        Sinclair,    
        Goebbels     
    }
    using Counters for Counters.Counter;

    address public executor;
 
    Counters.Counter private _tokenIdCounter;

    GlobalJournalistStats public stats;
    Article public articleContract;
 
    constructor(address statsAddress, address articleAddress) ERC721("Mentatz", "MZ") {
        stats = GlobalJournalistStats(statsAddress);
        articleContract = Article(articleAddress);
    }

    function safeMint(address to, string memory uri) public onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }
 
    // The following functions are overrides required by Solidity.
 
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }
 
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
    // This is a SoulBound Token, so we override the _beforeTokenTransfer function to block transfers.
    function _beforeTokenTransfer(
        address from, 
        address to, 
        uint256 tokenId
        ) internal override(ERC721) {
        require(from == address(0), "Mentatz: SBT - transfer blocked");
        super._beforeTokenTransfer(from, to, tokenId);
    }

    modifier onlyArticle() {                            
        require(msg.sender == address(articleContract), "Caller not Article");
        _;
    }

    function recordArticleResult( 
        address  author,
        bytes32  articleHash,
        bool     liked,
        bool     disliked,
        uint256  fraudFlags,
        uint256  lazyFlags
    ) external onlyArticle {
        JournalistStats storage js = journalistStats[author];

        js.articleHashList.push(articleHash);             

        js.totalArticles   += 1;
        js.totalLiked      += liked     ? 1 : 0;
        js.totalDisliked   += disliked  ? 1 : 0;
        js.totalFraudFlags += fraudFlags;
        js.totalLazyFlags  += lazyFlags;
    }

    
    event TagAssigned(address indexed author, TagId tag);
    event StatsUpdated(uint256 avgLikeRate, uint256 avgFraudRate, uint256 avgLazyRate, uint256 avgNotFlaggedRate, uint256 stdLikeRate, uint256 stdFraudRate, uint256 stdLazyRate, uint256 stdNotFlaggedRate);

    struct JournalistStats {
        uint256 totalArticles;
        uint256 totalLiked;
        uint256 totalDisliked;
        uint256 totalFraudFlags;
        uint256 totalLazyFlags;
        bytes32[] articleHashList; // List of all article hashes
        TagId tag;
    }


    mapping(address => JournalistStats) public journalistStats;

    function computeTagMapping(address author) public {
        
        JournalistStats storage js = journalistStats[author];

        if (js.totalArticles < 5) {
            js.tag = TagId.Amateur;
            emit TagAssigned(author, js.tag);
            return;
        }

        uint256 likeRate = (js.totalLiked * 100) / js.totalArticles;
        uint256 dislikeRate = (js.totalDisliked * 100) / js.totalArticles;
        uint256 fraudRate = (js.totalFraudFlags * 100) / js.totalArticles;
        uint256 lazyRate = (js.totalLazyFlags * 100) / js.totalArticles;
        uint256 notFlaggedRate = 100 - (fraudRate + lazyRate);
        
        uint256 avgLikeRate = stats.avgLikeRate();
        uint256 avgDislikeRate = stats.avgDislikeRate();
        uint256 avgFraudRate = stats.avgFraudRate();
        uint256 avgLazyRate = stats.avgLazyRate();
        uint256 avgNotFlaggedRate = stats.avgNotFlaggedRate();

        uint256 stdLikeRate = stats.stdLikeRate();
        uint256 stdDislikeRate = stats.stdDislikeRate();
        uint256 stdFraudRate = stats.stdFraudRate();
        uint256 stdLazyRate = stats.stdLazyRate();
        uint256 stdNotFlaggedRate = stats.stdNotFlaggedRate();

        emit StatsUpdated(avgLikeRate, avgFraudRate, avgLazyRate, avgNotFlaggedRate, stdLikeRate, stdFraudRate, stdLazyRate, stdNotFlaggedRate);

        // The Formula for determining the tag is as follows:
        int256 tagScore = 0;

        if (stdLikeRate > 0) {
            tagScore += int256((likeRate - avgLikeRate) * 1000 / stdLikeRate);
        }
        if (stdDislikeRate > 0) {
            tagScore -= int256((dislikeRate - avgDislikeRate) * 1000 / stdDislikeRate);
        }
        if (stdFraudRate > 0) {
            tagScore -= 5 * int256((fraudRate - avgFraudRate) * 1000 / stdFraudRate);
        }
        if (stdLazyRate > 0) {
            tagScore += 2 * int256((lazyRate - avgLazyRate) * 1000 / stdLazyRate);
        }

        if (tagScore > 3000) {
            js.tag = TagId.Sinclair;
        } else if (tagScore > 0) {
            js.tag = TagId.Rorschach;
        } else if (tagScore > -1500) { 
            js.tag = TagId.Yellow;
        } else if (tagScore < -1500) {
            js.tag = TagId.Goebbels;
        }

        emit TagAssigned(author, js.tag);

    }

    function getTag(address author) external view returns (TagId) {
        return journalistStats[author].tag;
    }
}
 