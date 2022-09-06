// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVentiSwapStakingV2 {
    struct ContractData {
        uint8 isActive;
        uint8 reentrant;
        uint64 timeFinished;
        uint64 baseMultiplier;
    }

    struct UserDeposit {
        uint8 lock;
        uint64 timestamp;
        uint256 staked;
        uint256 paid;
    }

    struct UserDepositByOwner {
        uint8 lock;
        uint64 timestamp;
        address account;
        uint256 staked;
        uint256 paid;
    }

    function stakingToken() external view returns (address);
    function totalSupply() external view returns (uint256);
    function totalRewards() external view returns (uint256);
    function baseMultiplier() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function getDeposit(address account) external view returns (UserDeposit memory);
    function isActive() external view returns (bool);
    function getMinimumStake() external view returns (uint256);
    function timeEnded() external view returns (uint256);
    function pendingReward(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function withdrawable(address account) external view returns (bool);
    function deposit(uint256 amount, uint8 lock) external;
    function withdraw(uint256 amount) external;
    function claimRewards() external;
    function emergencyWithdrawal() external;
    function updateMinimum(uint256 minimum) external;
    function fundStaking(uint256 amount) external;
    function withdrawRewardTokens() external;
    function closeRewards() external;
    function enableStaking() external;
    function stakeOnBehalfOf(address account, uint256 amount, uint32 timestamp, uint8 lock, uint256 paid) external;
    function stakeOnBehalfOfAll(UserDeposit[] calldata) external;
    function ownerAddStake(address account, uint256 amount) external;
    function ownerResetPaid(address account) external;

    event StakingFunded(uint256 amount);
    event StakingEnabled();
    event StakingEnded(uint256 timestamp);
    event RewardsClaimed(uint256 amount);
    event Deposited(address indexed account, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);
    event MinimumUpdated(uint256 newMinimum);
}