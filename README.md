# Mentatz

Mentatz is a decentralized journalism credibility platform built on Ethereum, leveraging a soulbound token-based system to measure, reward, and penalize article quality based on community-driven stakes and feedback.

## Objective

Establish Trustworthy Journalism: Create a transparent, tamper-resistant mechanism for evaluating article credibility using economic incentives.

Align Incentives: Encourage journalists to perform in-depth research and avoid misinformation by having readers stake ETH on article details.

Democratize Fact-Checking: Empower readers and expert critics to participate in a reputation system that reflects real-world research and fact-checking efforts.

Avoid Bias: Because of the prediction market style voting system, voters are incentivized to avoid downvoting quality articles or highlighting truths for lies since the consensus is what pays out in the end

## Implementation

1. Smart Contracts

Article Contract: Manages article submissions, staking windows, and finalization logic. Tracks two stakes:

Inflate Stake: ETH staked to support (upvote) the article.

Purge Stake: ETH staked to challenge (downvote) the article’s quality.

GlobalJournalistStats: Aggregates finalized article outcomes to compute moving averages and standard deviations for likes, fraud (lies in article) flags, and lazy (poor research reflected in article) flags.

Token Contract (Mentatz): ERC‑721 token soulbound token with identity tag

2. Workflow

Submission: Author submits an article hash to the Article contract.

Staking Period: Community members stake ETH to inflate or purge; critics optionally flag specific quotes as fraudulent or lazy research which are also voted on.

Oracle Blocking: To avoid users manipulating market outcomes, an oracle limits the users participation to 20 USD

Finalization: After the voting period, the contract calculates outcome ratios and emits a recordArticleResult event to the Mentatz contract.

Token Distribution: Contributors receive Mentatz tokens proportional to the distribution of funds at the time of the staking if in the consensus, otherwise no payout.

3. Identities

Skill Score: Smart contract computes Journalist Quality Score using Z-Scores of the authors liked, disliked, fraud flags, and lazy flags

Mapping to identity: Author is labeled one of the following -> Amateur, Yellow, Rorschach, Sinclair, Goebells

## Applications

Credibility Scores: Media outlets can display on‑chain credibility metrics alongside articles.

Access Points: Web3 or even current online newspapers can allow access to writing and editing based on tag and scoring

API Access: Third‑party tools can query on‑chain data to build credibility‑driven news aggregators or browser extensions.

## Roadmap & Future Development

Cross‑Chain Support: Expand beyond Ethereum to Layer‑2 networks for lower fees and faster finality.

Governance Module: Enable token holders to vote on parameter adjustments (e.g., staking thresholds, voting windows).

Merkle Tree Gas Efficiency: This current implementation is unrealistic at a large scale where O(n) and O(n^2) algorithms cost many ETH

Mobile Wallet Integration: Provide a lightweight mobile dApp for on‑the‑go article review.
