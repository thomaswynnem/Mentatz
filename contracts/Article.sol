// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

interface PriceOracle {
    function getLatestPrice() external view returns (int256);
    function DollarLimit(uint256 maxinput) external view returns (uint256);
}

interface Mentatz {
    function recordArticleResult(
        address author,
        bytes32 articleHash,
        bool    liked,
        bool    disliked,
        uint256 fraudFlags,
        uint256 lazyFlags
    ) external;
}

contract Article is ReentrancyGuard, Ownable {

    address public executor;
    modifier onlyOwnerOrGelato() {
        require(msg.sender == owner() || msg.sender == executor, "Not authorized");
        _;
    }

    PriceOracle public oracle;

    Mentatz public mentatz;

    constructor(address oracleAddress, address mentatzAddress) {
        oracle  = PriceOracle(oracleAddress);
        mentatz = Mentatz(mentatzAddress);
    }

    function setExecutor(address _executor) external onlyOwner {
        executor = _executor;
    }

    function fundGelatoExecutor() external payable onlyOwner {
        require(executor != address(0), "Executor not set");
        payable(executor).transfer(msg.value);
    }

    uint256 public currentMaxUSD      = 20;
    uint256 public currentCriticalFee = 5;
    address public feeCollector;

    event MaxUSDChanged(uint256 newMax);
    event CriticalFeeChanged(uint256 newFee);

    function changeMaxUSD(uint256 m)  external onlyOwner { currentMaxUSD = m; emit MaxUSDChanged(m); }
    function changeCriticalFee(uint256 f) external onlyOwner { currentCriticalFee = f; emit CriticalFeeChanged(f); }
    function setFeeCollector(address fc) external onlyOwner { feeCollector = fc; }

    function getOraclePrice(uint256 qty) public view returns (uint256) {
        return oracle.DollarLimit(qty);
    }

    // ────────────────────────────────────────────────────
    // On‑chain aggregates only
    // ────────────────────────────────────────────────────

    struct ArticleTotals {
        address author;
        uint256 inflateStake;
        uint256 purgeStake;
        uint256 fraudFlags;
        uint256 lazyFlags;
        bool    votingActive;
        uint256 startTime;
        uint256 votingPeriod;
    }

    mapping(bytes32 => ArticleTotals) public totals;

    mapping(bytes32 => uint256) public nextVoteIndex;

    mapping(bytes32 => uint256) public nextCriticIndex;

    mapping(bytes32 => bytes32) public merkleRoot;

    mapping(bytes32 => mapping(uint256 => bool)) public claimed;

    // ────────────────────────────────────────────────────
    // Events
    // ────────────────────────────────────────────────────

    event ArticleCreated(
        bytes32 indexed articleHash,
        address indexed author,
        uint256 startTime,
        uint256 votingPeriod
    );

    event ArticleVoted(
        bytes32 indexed articleHash,
        uint256 indexed voteIndex,
        address        voter,
        bool           inflate,
        uint256        amount,
        uint256        ratioAtVote
    );

    event ArticleCriticized(
        bytes32 indexed articleHash,
        uint256 indexed criticIndex,
        address        critic,
        string         quote,
        bool           fraudFlagged,
        bool           lazyFlagged
    );

    event CriticFunded(
        bytes32 indexed articleHash,
        uint256 indexed criticIndex,
        address        voter,
        bool           support,
        uint256        amount
    );

    event ArticleFinalized(
        bytes32 indexed articleHash,
        bool    liked,
        bool    disliked,
        uint256 totalInflateStake,
        uint256 totalPurgeStake,
        uint256 fraudFlags,
        uint256 lazyFlags,
        uint256 endTime
    );

    // ────────────────────────────────────────────────────
    // Lifecycle
    // ────────────────────────────────────────────────────

    function createArticle(bytes32 articleHash) external onlyOwner {
        require(!totals[articleHash].votingActive, "Already exists");
        totals[articleHash] = ArticleTotals({
            author:       msg.sender,
            inflateStake: 0,
            purgeStake:   0,
            fraudFlags:   0,
            lazyFlags:    0,
            votingActive: true,
            startTime:    block.timestamp,
            votingPeriod: 5 days
        });
        emit ArticleCreated(articleHash, msg.sender, block.timestamp, 5 days);
    }

    function vote(bytes32 articleHash, bool inflate) external payable {
        ArticleTotals storage t = totals[articleHash];
        require(t.votingActive, "Voting not active");
        require(msg.value > 0, "Send ETH to vote");

        if (inflate) {
            t.inflateStake += msg.value;
        } else {
            t.purgeStake += msg.value;
        }

        uint256 sum       = t.inflateStake + t.purgeStake;
        uint256 sideTotal = inflate ? t.inflateStake : t.purgeStake;
        uint256 ratio     = sum == 0 ? 0 : (sideTotal * 1000) / sum;

        uint256 idx = nextVoteIndex[articleHash]++;
        emit ArticleVoted(articleHash, idx, msg.sender, inflate, msg.value, ratio);
    }

    function criticize(bytes32 articleHash, string calldata quote, bool lazyFlagged, bool fraudFlagged) external payable {
        ArticleTotals storage t = totals[articleHash];
        require(t.votingActive, "Voting not active");

        uint256 minFee = getOraclePrice(currentCriticalFee);
        require(msg.value > minFee, "Insufficient critic fee");
        if (feeCollector != address(0)) {
            payable(feeCollector).transfer(msg.value);
        }

        uint256 idx = nextCriticIndex[articleHash]++;
        if (fraudFlagged) t.fraudFlags++;
        else if (lazyFlagged) t.lazyFlags++;
        else revert("Must flag fraud or lazy");

        emit ArticleCriticized(articleHash, idx, msg.sender, quote, fraudFlagged, lazyFlagged);
    }

    function fundCritic(bytes32 articleHash, uint256 criticIndex, bool support) external payable {
        ArticleTotals storage t = totals[articleHash];
        require(t.votingActive, "Voting not active");
        require(msg.value > 0, "Send ETH to fund");

        emit CriticFunded(articleHash, criticIndex, msg.sender, support, msg.value);
    }

    function finalizeArticle(bytes32 articleHash) external onlyOwnerOrGelato {
        ArticleTotals storage t = totals[articleHash];
        require(t.votingActive, "Not active");
        require(block.timestamp >= t.startTime + t.votingPeriod, "Period not ended");

        t.votingActive = false;

        uint256 total = t.inflateStake + t.purgeStake;
        bool liked    = total > 0 && (t.inflateStake * 100 / total) > 75;
        bool disliked = total > 0 && (t.purgeStake  * 100 / total) > 75;

        emit ArticleFinalized(
            articleHash,
            liked,
            disliked,
            t.inflateStake,
            t.purgeStake,
            t.fraudFlags,
            t.lazyFlags,
            block.timestamp
        );

        mentatz.recordArticleResult(
            t.author,
            articleHash,
            liked,
            disliked,
            t.fraudFlags,
            t.lazyFlags
        );
    }

    // ────────────────────────────────────────────────────
    // Claiming via Merkle
    // ────────────────────────────────────────────────────

    function setMerkleRoot(bytes32 articleHash, bytes32 root) external onlyOwner {
        merkleRoot[articleHash] = root;
    }

    function claim(bytes32   articleHash, uint256   voteIndex,address   voter,uint256   payout, bytes32[] calldata proof) external nonReentrant {
        require(msg.sender == voter, "Not your claim");
        require(!claimed[articleHash][voteIndex], "Already claimed");

        bytes32 leaf = keccak256(abi.encodePacked(voteIndex, voter, payout));
        require(
            MerkleProof.verify(proof, merkleRoot[articleHash], leaf),
            "Invalid proof"
        );

        claimed[articleHash][voteIndex] = true;
        payable(voter).transfer(payout);
    }
}