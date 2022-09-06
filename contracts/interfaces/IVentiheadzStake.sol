// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVentiheadzStake {
    struct ContractData {
        uint8 isActive;
        uint8 mutex;
        uint16 maxStake;
        uint16 totalStaked;
        uint32 timeEnded;
        uint128 monthlyReward;
    }

    struct UserData {
        uint16 totalStaked;
        uint16 id1;
        uint16 id2;
        uint16 id3;
        uint16 id4;
        uint16 id5;
        uint32 timeStaked;
    }

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function getUnlockTime(address account) external view returns (uint256);
    function tokensStaked(address account) external view returns (uint256[] memory);
    function isActive() external view returns (bool);
    function getMaxStake() external view returns (uint16);
    function timeEnded() external view returns (uint32);
    function withdrawable(address account) external view returns (bool);
    function pendingReward(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function stakeToken(uint16 tokenId) external;
    function stakeMany(uint16[] memory tokenIds) external;
    function claimReward() external;
    function withdraw(uint16 tokenId) external;
    function withdrawAll() external;
    function emergencyWithdrawal() external;
    function addRewardTokens(uint256 amount) external;
    function setActive() external;
    function endStaking() external;
    function removeRewardTokens(uint256 amount) external;

    event RewardsAdded(uint256 amount);
    event RewardsRemoved(uint256 amount);
    event RewardsPaid(address indexed owner, uint256 amount);
    event NFTStaked(address indexed owner, uint256 nftId);
    event NFTWithdrawn(address indexed owner, uint256 nftId);
    event RewardsClaimed(address indexed owner, uint256 rewards);
}