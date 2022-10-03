// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IERC721.sol";
import "./interfaces/IERC721Receiver.sol";
import "./interfaces/IVentiheadzStake.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/Math.sol";
import "./libraries/NFTStake.sol";

contract VentiHeadzStake is IERC721Receiver, IVentiheadzStake {
    using SafeERC20 for IERC20;
    using NFTStake for UserData;

    IERC20 private constant VST = IERC20(0xb7C2fcD6d7922eddd2A7A9B0524074A60D5b472C);
    // IERC721 private constant VENTI_HEADZ = IERC721(0x1343248Cbd4e291C6979e70a138f4c774e902561);
    IERC721 private VENTI_HEADZ;
    ContractData private _data;

    address private _owner;
    uint256 private _totalRewards;
    mapping (address => UserData) private _deposits;
    mapping (address => uint256) private _rewardPaid;

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

    modifier nonReentrant() {
        require(_data.mutex == 1, "Nonreentrant");
        _data.mutex = 2;
        _;
        _data.mutex = 1;
    }

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
    function tokensStaked(address account) public view returns (uint256[] memory)
    {
        UserData memory userDeposit = _deposits[account];

        return userDeposit.stakedTokens();
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
    function withdrawable(address account) public view returns (bool)
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

        return user.pendingReward(_data.monthlyReward);
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

        return user.earned(rewardsPaid, _data.monthlyReward, endTime);
    }

    /**
     * @dev Stakes NFT in contract
     *
     * @param tokenId the id of the NFT to stake
     *
     * @notice Checks if user has already staked. If so, claim rewards and reset
     * claimed rewards to 0 and timestamp to current block.
     */
    function stakeToken(uint16 tokenId) external nonReentrant
    {
        VENTI_HEADZ.safeTransferFrom(msg.sender, address(this), tokenId);

        UserData storage user = _deposits[msg.sender];

        require(user.totalStaked + 1 <= 5, "Max stake exceeded");

        if (user.totalStaked == 0) user.id1 = tokenId;
        else if (user.totalStaked == 1) user.id2 = tokenId;
        else if (user.totalStaked == 2) user.id3 = tokenId;
        else if (user.totalStaked == 3) user.id4 = tokenId;
        else if (user.totalStaked == 4) user.id5 = tokenId;

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

        _data.totalStaked += 1;
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
    function stakeMany(uint16[] memory tokenIds) external nonReentrant
    {   
        UserData storage user = _deposits[msg.sender];

        uint256 total = user.totalStaked;

        require(total + tokenIds.length < 5, "Exceeding max stake");

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

        for (uint i = 0; i < tokenIds.length;) {
            VENTI_HEADZ.safeTransferFrom(msg.sender, address(this), tokenIds[i]);

            if (total == 0) {
                user.id1 = tokenIds[i];
            } else if (total == 1) {
                user.id2 = tokenIds[i];
            } else if (total == 2) {
                user.id3 = tokenIds[i];
            } else if (total == 3) {
                user.id4 = tokenIds[i];
            } else if (total == 4) {
                user.id5 = tokenIds[i];
            }
            
            emit NFTStaked(msg.sender, tokenIds[i]);

            unchecked { ++total; }
            unchecked { ++i; }
        }

        _data.totalStaked += uint16(tokenIds.length);
        user.totalStaked += uint16(tokenIds.length);
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
    function withdraw(uint16 tokenId) external nonReentrant
    {
        UserData storage user = _deposits[msg.sender];
        require(withdrawable(msg.sender), "NFTs still locked");
        
        uint256 reward = earned(msg.sender);
        require(user.withdrawId(tokenId));

        VENTI_HEADZ.safeTransferFrom(address(this), msg.sender, tokenId);
        _data.totalStaked -= 1;

        if (user.totalStaked == 0) {
            delete _deposits[msg.sender];
        }
        else {
            if (reward > 0) {
                _rewardPaid[msg.sender] += reward;
                _totalRewards -= reward;

                VST.safeTransfer(msg.sender, reward);

                emit RewardsPaid(msg.sender, reward);
            }

            uint256 endTime = _data.timeEnded == 0 ? block.timestamp : _data.timeEnded;
            _rewardPaid[msg.sender] = user.earned(0, _data.monthlyReward, endTime);
        }

        emit NFTWithdrawn(msg.sender, tokenId);
    }

    /**
     * @dev Withdraws all staked NFTs for user
     *
     * @notice removes all staked NFTs, claims all outstanding rewards, and
     * resets all data to 0.
     */
    function withdrawAll() external nonReentrant
    {
        UserData storage user = _deposits[msg.sender];
        
        require(user.totalStaked > 0, "No tokens staked");
        require(withdrawable(msg.sender), "NFTs still locked");

        uint256 reward = earned(msg.sender);
        _rewardPaid[msg.sender] = 0;

        if (reward > 0) {
            _totalRewards -= reward;

            VST.transfer(msg.sender, reward);

            emit RewardsPaid(msg.sender, reward);
        }

        uint16 total = user.totalStaked;
        user.totalStaked = 0;

        if (total > 0) {
            VENTI_HEADZ.safeTransferFrom(address(this), msg.sender, user.id1);
            emit NFTWithdrawn(msg.sender, user.id1);
        }
        if (total > 1) {
            VENTI_HEADZ.safeTransferFrom(address(this), msg.sender, user.id2);
            emit NFTWithdrawn(msg.sender, user.id2);
        }
        if (total > 2) {
            VENTI_HEADZ.safeTransferFrom(address(this), msg.sender, user.id3);
            emit NFTWithdrawn(msg.sender, user.id3);
        }
        if (total > 3) {
            VENTI_HEADZ.safeTransferFrom(address(this), msg.sender, user.id4);
        }
        if (total > 4) {
            VENTI_HEADZ.safeTransferFrom(address(this), msg.sender, user.id5);
        }

        delete _deposits[msg.sender];

        _data.totalStaked -= total;
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
        require(_data.timeEnded > 0, "Contract still active");

        uint256 total = user.totalStaked;
        user.totalStaked = 0;

        if (total > 0) {
            VENTI_HEADZ.safeTransferFrom(address(this), msg.sender, user.id1);
            emit NFTWithdrawn(msg.sender, user.id1);
        }
        if (total > 1) {
            VENTI_HEADZ.safeTransferFrom(address(this), msg.sender, user.id2);
            emit NFTWithdrawn(msg.sender, user.id2);
        }
        if (total > 2) {
            VENTI_HEADZ.safeTransferFrom(address(this), msg.sender, user.id3);
            emit NFTWithdrawn(msg.sender, user.id3);
        }
        if (total > 3) {
            VENTI_HEADZ.safeTransferFrom(address(this), msg.sender, user.id4);
        }
        if (total > 4) {
            VENTI_HEADZ.safeTransferFrom(address(this), msg.sender, user.id5);
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

        VST.safeTransferFrom(msg.sender, address(this), amount);
        _totalRewards += amount;

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
}
