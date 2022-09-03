// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IERC721.sol";
import "./interfaces/IERC721Receiver.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/Math.sol";

contract VentiHeadzStake is IERC721Receiver {
    using SafeERC20 for IERC20;

    IERC20 private constant VST = IERC20(0xb7C2fcD6d7922eddd2A7A9B0524074A60D5b472C);
    // IERC721 private constant VENTI_HEADZ = IERC721(0x1343248Cbd4e291C6979e70a138f4c774e902561);
    IERC721 private VENTI_HEADZ;
    ContractData private _data;

    address private _owner;
    uint256 private _totalRewards;
    mapping (address => UserData) private _deposits;
    mapping (address => uint256) private _rewardPaid;
    
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
        uint32 timeStaked;
        uint16[] tokens;
    }

    constructor (address nft_) {
        _data.isActive = 1;
        _data.mutex = 1;
        _data.maxStake = 5;
        _data.monthlyReward = 100e18;

        VENTI_HEADZ = IERC721(nft_);
        _owner = msg.sender;
    }

    fallback() external {}
    receive() external payable {}

    /**
     * @dev Get total amount of NFTs staked
     *
     * @return totalStaked total NFTs staked
     */
    function totalSupply() external view returns (uint256)
    {
        return _data.totalStaked;
    }

    /**
     * @dev Find the amount of NFTs staked by account
     *
     * @param account the account to lookup
     *
     * @return staked the amount of NFTs staked by account
     */
    function balanceOf(address account) external view returns (uint256)
    {
        return _deposits[account].totalStaked;
    }

    /**
     * @dev Find the unlock time for an account
     *
     * @param account the account to lookup
     *
     * @return timestamp the timestamp at which NFTs unlock
     *
     * @notice if a user re-stakes an additional NFT, rewards are claimed
     * and the block timestamp is restarted
     */
    function getUnlockTime(address account) public view returns (uint256)
    {
        return _deposits[account].timeStaked + (2628000 * 12);
    }

    /**
     * @dev Find the ids of the staked NFTs by an account
     *
     * @param account the account to lookup
     *
     * @return tokenIds the list of token ids staked by the account
     */
    function tokensStaked(address account) external view returns (uint16[] memory)
    {
        return _deposits[account].tokens;
    }

    /**
     * @dev Checks if staking contract is active
     *
     * @return isActive returns status
     */
    function isActive() external view returns (bool)
    {
        return _data.isActive == 1 ? true : false;
    }

    /**
     * @dev Checks the maximum allowable stake
     *
     * @return maxStake the number of NFTs an account can stake
     */
    function getMaxStake() external view returns (uint16)
    {
        return _data.maxStake;
    }

    /**
     * @dev Checks the timestamp that staking ended
     *
     * @return timestamp the end timestamp
     *
     * @notice returns 0 if still active
     */
    function timeEnded() external view returns (uint32)
    {
        return _data.timeEnded;
    }

    /**
     * @dev Checks if an account can withdraw NFTs
     *
     * @param account the account to lookup
     *
     * @return canWithdraw whether user can withdraw or not
     */
    function withdrawable(address account) external view returns (bool)
    {
        uint256 unlockTime = getUnlockTime(account);

        if (unlockTime <= block.timestamp) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Checks pending rewards for current period
     *
     * @param account the account to lookup
     *
     * @return pendingReward the pending reward for current period
     *
     * @notice users can only withdraw after 3 months. This value is a prorated
     * reward but is non-claimable. When users re-stake, this pending reward is
     * claimed and sent to the user.
     */
    function pendingReward(address account) public view returns (uint256)
    {
        if (_data.timeEnded > 0) {
            return 0;
        }

        UserData memory user = _deposits[account];

        if (user.totalStaked == 0) {
            return 0;
        }

        uint256 timePassed = block.timestamp - user.timeStaked;
        uint256 periodsPassed = timePassed > 0 ? Math.floorDiv(timePassed, 7884000) : 0;
        uint256 interimTime = timePassed - (periodsPassed * 7884000);
        uint256 pending = user.totalStaked * (_data.monthlyReward * 3) * interimTime / 7884000;

        return pending;
    }

    /**
     * @dev Checks claimable rewards for account
     *
     * @param account the account to lookup
     *
     * @return reward the claimable reward from past periods
     */
    function earned(address account) public view returns (uint256)
    {
        UserData memory user = _deposits[account];
        
        uint256 rewardsPaid = _rewardPaid[account];
        uint256 endTime = _data.timeEnded == 0 ? block.timestamp : _data.timeEnded;
        uint256 periodsPassed = Math.floorDiv(endTime - user.timeStaked, 7884000);

        if (periodsPassed == 0) {
            return 0;
        }

        uint256 totalReward = user.totalStaked * (_data.monthlyReward * 3) - rewardsPaid;

        return totalReward;
    }

    /**
     * @dev Stakes NFT in contract
     *
     * @param tokenId the id of the NFT to stake
     *
     * @notice Checks if user has already staked. If so, claim rewards and reset
     * claimed rewards to 0 and timestamp to current block.
     */
    function stakeToken(uint16 tokenId) external
    {
        UserData storage user = _deposits[msg.sender];

        require(user.totalStaked + 1 <= _data.maxStake, "You've reached the max stake");

        if (user.totalStaked > 0) {
            uint256 pending = pendingReward(msg.sender);
            uint256 reward = earned(msg.sender);
            uint256 combined = pending + reward;
            
            if (combined > 0) {
                _rewardPaid[msg.sender] = 0;
                _totalRewards -= combined;
                VST.transfer(msg.sender, combined);            
            }
        }

        VENTI_HEADZ.safeTransferFrom(msg.sender, address(this), tokenId);

        user.tokens.push(tokenId);
        user.totalStaked += 1;
        user.timeStaked = uint32(block.timestamp);

        emit NFTStaked(msg.sender, tokenId);
    }

    /**
     * @dev Stakes multiple NFTs in contract
     *
     * @param tokenIds list of tokenIds to stake
     *
     * @notice Checks if user has already staked. If so, claim rewards and reset
     * claimed rewards to 0 and timestamp to current block.
     */
    function stakeMany(uint16[] memory tokenIds) external
    {
        require(tokenIds.length < 6, "Maximum 5 NFTs at once");
        
        UserData storage user = _deposits[msg.sender];

        if (user.totalStaked > 0) {
            uint256 pending = pendingReward(msg.sender);
            uint256 reward = earned(msg.sender);
            uint256 combined = pending + reward;
            
            if (combined > 0) {
                _rewardPaid[msg.sender] = 0;
                _totalRewards -= combined;
                VST.transfer(msg.sender, combined);        
            }            
        }
        
        uint256 totalTokens = tokenIds.length;

        for (uint i = 0; i < totalTokens;) {
            VENTI_HEADZ.safeTransferFrom(msg.sender, address(this), tokenIds[i]);
            user.tokens.push(tokenIds[i]);
            
            emit NFTStaked(msg.sender, tokenIds[i]);

            unchecked { ++i; }
        }

        user.totalStaked += uint16(totalTokens);
        user.timeStaked = uint32(block.timestamp);
    }

    /**
     * @dev Claims earned rewards for account
     */
    function claimReward() external
    {
        uint256 reward = earned(msg.sender);

        if (reward > 0) {
            _rewardPaid[msg.sender] += reward;
            _totalRewards -= reward;

            VST.safeTransfer(msg.sender, reward);

            emit RewardsPaid(msg.sender, reward);
        }
    }

    /**
     * @dev Withdraws staked NFT
     *
     * @param tokenId the NFT id to withdraw to user
     *
     * @notice it finds the index of the nft id, replaces and
     * removes it from the list.
     */
    function withdraw(uint16 tokenId) external
    {
        UserData storage user = _deposits[msg.sender];

        uint256 index = 6;

        for (uint i = 0; i < user.tokens.length;) {
            if (user.tokens[i] == tokenId) {
                index = i;
                break;
            }

            unchecked { ++i; }
        }

        require(index < 6, "Token ID not staked by user");

        user.tokens[index] = user.tokens[user.tokens.length - 1];
        user.tokens.pop();
        user.totalStaked -= 1;

        VENTI_HEADZ.safeTransferFrom(address(this), msg.sender, tokenId);

        emit NFTWithdrawn(msg.sender, tokenId);
    }

    /**
     * @dev Withdraws all staked NFTs for user
     *
     * @notice removes all staked NFTs, claims all outstanding rewards, and
     * resets all data to 0.
     */
    function withdrawAll() external
    {
        UserData storage user = _deposits[msg.sender];
        
        require(user.totalStaked > 0, "No tokens staked");

        uint256 reward = earned(msg.sender);

        if (reward > 0) {
            _rewardPaid[msg.sender] = 0;
            _totalRewards -= reward;

            VST.transfer(msg.sender, reward);

            emit RewardsPaid(msg.sender, reward);
        }

        for (uint i = 0; i < user.tokens.length;) {
            VENTI_HEADZ.safeTransferFrom(address(this), msg.sender, user.tokens[i]);

            emit NFTWithdrawn(msg.sender, user.tokens[i]);

            unchecked { ++i; }
        }

        delete _deposits[msg.sender];
    }

    /**
     * @dev Function to be used if there are no rewards left in contract
     *
     * @notice Users should only use this function as a last resort. If possible,
     * use regular withdrawal.
     */
    function emergencyWithdrawal() external
    {
        UserData storage user = _deposits[msg.sender];

        require(user.totalStaked > 0, "No tokens staked");

        for (uint i = 0; i < user.tokens.length;) {
            VENTI_HEADZ.safeTransferFrom(address(this), msg.sender, user.tokens[i]);

            emit NFTWithdrawn(msg.sender, user.tokens[i]);

            unchecked { ++i; }
        }

        delete _deposits[msg.sender];
    }

    /**
     * @dev Adds rewards token to contract
     *
     * @param amount amount of tokens to transfer
     *
     * @notice owner only function
     */
    function addRewardTokens(uint256 amount) external
    {
        require(msg.sender == _owner, "Must be owner");

        _totalRewards += amount;

        VST.safeTransferFrom(msg.sender, address(this), amount);

        emit RewardsAdded(amount);
    }

    /**
     * @dev Marks the staking contract as active
     *
     * @notice 1 = inactive; 2 = active
     */
    function setActive() external
    {
        require(msg.sender == _owner, "Must be owner");
        require(_data.timeEnded == 0, "Staking already finished");

        _data.isActive = 2;
    }

    /**
     * @dev Closes staking contract at block timestamp
     *
     * @notice This is a one-way function that cannot be undone
     */
    function endStaking() external
    {
        require(msg.sender == _owner, "Must be owner");

        _data.isActive = 1;
        _data.timeEnded = uint32(block.timestamp);
    }

    /**
     * @dev Allows user to remove reward tokens from contract
     *
     * @notice Contract owner should ensure there are always enough
     * reward tokens to pay users' yield.
     */
    function removeRewardTokens(uint256 amount) external
    {
        require(msg.sender == _owner, "Must be owner");

        _totalRewards -= amount;

        VST.transfer(msg.sender, amount);

        emit RewardsRemoved(amount);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // ##### EVENTS ##### //

    event RewardsAdded(uint256 amount);
    event RewardsRemoved(uint256 amount);
    event RewardsPaid(address indexed owner, uint256 amount);
    event NFTStaked(address indexed owner, uint256 nftId);
    event NFTWithdrawn(address indexed owner, uint256 nftId);
    event RewardsClaimed(address indexed owner, uint256 rewards);
}