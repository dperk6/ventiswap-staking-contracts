//SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "hardhat/console.sol";
import "./libraries/Math.sol";
import "./libraries/Ownable.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/IERC20.sol";

// solhint-disable not-rely-on-time, avoid-low-level-calls
contract VentiStakeV2 is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public stakingToken; // Staking token

    uint256 private _totalSupply; // Total staked amount
    uint256 private _totalRewards;  // Total amount for rewards
    uint256 private _stakeRequired = 100e18; // Minimum stake amount

    // Set standard contract data in ContractData struct
    ContractData private _data = ContractData({
        isActive: 2, // 1 = true, 2 = false
        reentrant: 1, // 1 = ready, 2 = busy
        timeFinished: 0,
        baseMultiplier: 1e16
    });

    mapping (address => UserDeposit) private _deposits; // Track all user deposits

    // Store global contract data in packed struct
    struct ContractData {
        uint8 isActive;
        uint8 reentrant;
        uint64 timeFinished;
        uint64 baseMultiplier;
    }

    // Store user deposit data in packed struct
    struct UserDeposit {
        uint8 lock; // 1 = 1 month; 2 = 3 month; 3 = 6 month
        uint64 timestamp;
        uint256 staked;
        uint256 paid;
    }

    // This is for migrating existing stakers to new token
    struct UserDepositByOwner {
        uint8 lock;
        uint64 timestamp;
        address account;
        uint256 staked;
        uint256 paid;
    }

    constructor(IERC20 stakingToken_) {
        stakingToken = stakingToken_;
    }

    // ===== MODIFIERS ===== //

    /**
     * @dev Reentrancy protection
     */
    modifier nonReentrant()
    {
        require(_data.reentrant == 1, "Reentrancy not allowed");
        _data.reentrant = 2;
        _;
        _data.reentrant = 1;
    }

    // ===== PAYABLE DEFAULTS ====== //

    fallback() external payable {
        owner().call{value: msg.value}("");
    }

    receive() external payable {
        owner().call{value: msg.value}("");
    }

    // ===== VIEW FUNCTIONS ===== //

    /**
     * @dev Check total amount staked
     *
     * @return totalSupply the total amount staked
     */
    function totalSupply() external view returns (uint256)
    {
        return _totalSupply;
    }

    /**
     * @dev Check total rewards amount
     *
     * @notice this assumes that staking token is the same as reward token
     *
     * @return totalRewards the total balance of contract - amount staked
     */
    function totalRewards() external view returns (uint256)
    {
        return _totalRewards;
    }

    /**
     * @dev Check base multiplier of contract
     *
     * @notice Normalized to 1e18 = 100%. Contract currently uses a 1x, 2x, and 3x multiplier
     * based on how long the user locks their stake for (in UserDeposit struct).
     * Therefore max baseMultiplier would be <= 333e15 (33.3%).
     *
     * @return baseMultiplier 1e18 normalized percentage to start 
     */
    function baseMultiplier() external view returns (uint256)
    {
        return _data.baseMultiplier;
    }

    /**
     * @dev Checks amount staked for account.
     *
     * @param account the user account to look up.
     *
     * @return staked the total amount staked from account.
     */
    function balanceOf(address account) external view returns (uint256)
    {
        return _deposits[account].staked;
    }

    /**
     * @dev Checks all user deposit data for account.
     *
     * @param account the user account to look up.
     *
     * @return userDeposit the entire deposit data.
     */
    function getDeposit(address account) external view returns (UserDeposit memory)
    {
        return _deposits[account];
    }

    /**
     * @dev Checks if staking contract is active.
     *
     * @notice _isActive is stored as uint where 1 = true; 2 = false.
     *
     * @return isActive boolean true if 1; false if not.
     */
    function isActive() external view returns (bool)
    {
        return _data.isActive == 1;
    }

    /**
     * @dev Check current minimum stake amount
     *
     * @return minimum the min stake amount
     */
    function getMinimumStake() external view returns (uint256)
    {
        return _stakeRequired;
    }

    /**
     * @dev Checks when staking finished.
     *
     * @notice if 0, staking is still active.
     *
     * @return timeFinished the block timestamp of when staking completed.
     */
    function timeEnded() external view returns (uint256)
    {
        return _data.timeFinished;
    }

    /**
     * @dev Checks pending rewards currently accumulating for month.
     *
     * @notice These rewards are prorated for the current period (month).
     * Users cannot withdraw rewards until a full month has passed.
     * If a user makes an additional deposit mid-month, these pending rewards
     * will be added to their new staked amount, and lock time reset.
     *
     * @param account the user account to use for calculation.
     *
     * @return pending the pending reward for the current period.
     */
    function pendingReward(address account) public view returns (uint256)
    {
        // If staking rewards are finished, should always return 0
        if (_data.timeFinished > 0) {
            return 0;
        }

        // Get deposit record for account
        UserDeposit memory userDeposit = _deposits[account];

        if (userDeposit.staked == 0) {
            return 0;
        }

        // Calculate total time, months, and time delta between
        uint256 timePassed = block.timestamp - userDeposit.timestamp;
        uint256 monthsPassed = timePassed > 0 ? Math.floorDiv(timePassed, 2628000) : 0;
        uint256 interimTime = timePassed - (monthsPassed * 2628000);

        // Calculate pending rewards based on prorated time from the current month
        uint256 pending = userDeposit.staked * (_data.baseMultiplier * uint256(userDeposit.lock)) / 1e18 * interimTime / 2628000;

        return pending;
    }

    /**
     * @dev Checks current earned rewards for account.
     *
     * @notice These rewards are calculated by the number of full months
     * passed since deposit, based on the multiplier set by the user based on
     * lockup time (i.e. 1x for 1 month, 2x for 3 months, 3x for 6 months).
     * This function subtracts withdrawn rewards from the calculation so if
     * total rewards are 100 coins, but 50 are withdrawn,
     * it should return 50.
     *
     * @param account the user account to use for calculation.
     *
     * @return totalReward the total rewards the user has earned.
     */
    function earned(address account) public view returns (uint256)
    {
        // Get deposit record for account
        UserDeposit memory userDeposit = _deposits[account];
        
        // Get total rewards paid already
        uint256 rewardPaid = userDeposit.paid;

        // If a final timestamp is set, use that instead of current timestamp
        uint256 endTime = _data.timeFinished == 0 ? block.timestamp : _data.timeFinished;
        uint256 monthsPassed = Math.floorDiv(endTime - userDeposit.timestamp, 2628000);

        // If no months have passed, return 0
        if (monthsPassed == 0) return 0;

        // Calculate total earned - amount already paid
        uint256 totalReward = userDeposit.staked * ((_data.baseMultiplier * userDeposit.lock) * monthsPassed) / 1e18 - rewardPaid;
        
        return totalReward;
    }

    /**
     * @dev Check if user can withdraw their stake.
     *
     * @notice uses the user's lock chosen on deposit, multiplied
     * by the amount of seconds in a month.
     *
     * @param account the user account to check.
     *
     * @return canWithdraw boolean value determining if user can withdraw stake.
     */
    function withdrawable(address account) public view returns (bool)
    {
        UserDeposit memory userDeposit = _deposits[account];
        uint256 unlockTime = _getUnlockTime(userDeposit.timestamp, userDeposit.lock);
        
        if (block.timestamp < unlockTime) {
            return false;
        } else {
            return true;
        }
    }

    /**
     * @dev Check if current time past lock time.
     *
     * @param timestamp the user's initial lock time.
     * @param lock the lock multiplier chosen (1 = 1 month, 2 = 3 month, 3 = 6 month).
     *
     * @return unlockTime the timestamp after which a user can withdraw.
     */
    function _getUnlockTime(uint64 timestamp, uint8 lock) private pure returns (uint256)
    {
        if (lock == 1) {
            // Add one month
            return timestamp + 2628000;
        } else if (lock == 2) {
            // Add three months
            return timestamp + (2628000 * 3);            
        } else {
            // Add six months
            return timestamp + (2628000 * 6);
        }
    }

    // ===== MUTATIVE FUNCTIONS ===== //

    /**
     * @dev Deposit and stake funds
     *
     * @param amount the amount of tokens to stake
     * @param lock the lock multiplier (1 = 1 month, 2 = 3 month, 3 = 6 month).
     *
     * @notice Users cannot change lock periods if adding additional stake
     */
    function deposit(uint256 amount, uint8 lock) external payable nonReentrant
    {
        // Check if staking is active
        require(_data.isActive == 1, "Staking inactive");
        require(lock > 0 && lock < 4, "Lock must be 1, 2, or 3");
        require(amount > 0, "Amount cannot be 0");

        // Get existing user deposit. All 0s if non-existent
        UserDeposit storage userDeposit = _deposits[msg.sender];

        require(userDeposit.staked + amount >= _stakeRequired, "Need to meet minimum stake");

        // Transfer token
        stakingToken.transferFrom(msg.sender, address(this), amount);

        // If user's current stake is greater than 0, we need to get
        // earned and pending rewards and add them to stake and total
        if (userDeposit.staked > 0) {
            uint256 earnedAmount = earned(msg.sender);
            uint256 pendingAmount = pendingReward(msg.sender);
            uint256 combinedAmount = earnedAmount + pendingAmount;

            // Update total rewards by subtracting earned/pending amounts
            _totalRewards -= combinedAmount;

            // Update total supply and current stake
            _totalSupply += amount + combinedAmount;

            // Lock is only updated if value is passed is greater than existing, or if user's stake is unlocked
            if (lock > userDeposit.lock || block.timestamp > _getUnlockTime(userDeposit.timestamp, userDeposit.lock)) {
                userDeposit.lock = lock;
            }

           // Save new deposit data
            userDeposit.staked += amount + combinedAmount;
            userDeposit.timestamp = uint64(block.timestamp);

            // Reset user's claimed amount
            userDeposit.paid = 0;
        } else {
            // Create new deposit record for user with new lock time
            userDeposit.lock = lock;
            userDeposit.timestamp = uint64(block.timestamp);
            userDeposit.staked = amount;
            userDeposit.paid = 0;

            // Add new amount to total supply
            _totalSupply += amount;
        }

        emit Deposited(msg.sender, amount);
    }

    /**
     * @dev Withdraws a user's stake.
     *
     * @param amount the amount to withdraw.
     *
     * @notice must be past unlock time.
     */
    function withdraw(uint256 amount) external payable nonReentrant
    {
        // Get user deposit info in storage
        UserDeposit storage userDeposit = _deposits[msg.sender];

        // Check if user can withdraw amount
        require(userDeposit.staked > 0, "User has no stake");
        require(withdrawable(msg.sender), "Lock still active");
        require(amount <= userDeposit.staked, "Withdraw amount too high");

        // Get earned rewards and paid rewards
        uint256 earnedRewards = earned(msg.sender);

        // Calculate amount to withdraw
        uint256 amountToWithdraw = amount + earnedRewards;

        // Check if user is withdrawing their total stake
        if (userDeposit.staked == amount) {
            // If withdrawing full amount we reset paid rewards and stakes
            // Other information will be overwritten during deposit
            userDeposit.paid = 0;
            userDeposit.staked = 0;
        } else {
            uint256 monthsForStaking;
            if (userDeposit.lock == 1) {
                monthsForStaking = 1;
            } else if (userDeposit.lock == 2) {
                monthsForStaking = 3;
            } else if (userDeposit.lock == 3) {
                monthsForStaking = 6;
            }

            // Remove amount from staked
            userDeposit.staked -= amount;

            // Reset paid amount since it is used in earned()
            userDeposit.paid = 0;

            // Set paid amount to 100% of earned rewards to date
            userDeposit.paid = earned(msg.sender);
        }

        // Update total staked amount and rewards amount
        _totalSupply -= amount;
        _totalRewards -= earnedRewards;

        // Transfer tokens to user
        stakingToken.safeTransfer(msg.sender, amountToWithdraw);

        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @dev Emergency withdrawal in case rewards have been pulled
     *
     * @notice Only available after staking is closed and
     * all reward tokens have been withdrawn.
     */
    function emergencyWithdrawal() external payable
    {
        require(_data.isActive == 2, "Staking must be closed");
        require(_data.timeFinished > 0, "Staking must be closed");
        require(_totalRewards == 0, "Use normal withdraw");

        UserDeposit storage userDeposit = _deposits[msg.sender];

        uint256 amountToWithdraw = userDeposit.staked;

        require(amountToWithdraw > 0, "No stake to withdraw");

        // Reset all data
        userDeposit.paid = 0;
        userDeposit.staked = 0;

        // Update total staked amount
        _totalSupply -= amountToWithdraw;

        // Transfer tokens to user
        stakingToken.safeTransfer(msg.sender, amountToWithdraw);

        emit Withdrawal(msg.sender, amountToWithdraw);
    }

    /**
     * @dev Claims earned rewards.
     */
    function claimRewards() external payable nonReentrant
    {
        // Get user's earned rewards
        uint256 amountToWithdraw = earned(msg.sender);
        
        require(amountToWithdraw > 0, "No rewards to withdraw");
        require(amountToWithdraw <= _totalRewards, "Not enough rewards in contract");

        // Add amount to user's withdraw rewards
        _deposits[msg.sender].paid += amountToWithdraw;

        // Update total rewards
        _totalRewards -= amountToWithdraw;

        stakingToken.safeTransfer(msg.sender, amountToWithdraw);

        emit RewardsClaimed(amountToWithdraw);
    }

    /**
     * @dev Update minimum stake amount
     *
     * @param minimum the new minimum stake account
     */
    function updateMinimum(uint256 minimum) external payable onlyOwner
    {
        _stakeRequired = minimum;
        
        emit MinimumUpdated(minimum);
    }

    /**
     * @dev Funds rewards for contract
     *
     * @param amount the amount of tokens to fund
     */
    function fundStaking(uint256 amount) external payable onlyOwner
    {
        require(amount > 0, "Amount cannot be 0");

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        _totalRewards += amount;

        emit StakingFunded(amount);
    }

    /**
     * @dev Withdraws rewards tokens
     *
     * @notice Requires rewards to be closed. This
     * function is intended to pull leftover tokens
     * once all users have claimed rewards.
     */
    function withdrawRewardTokens() external payable onlyOwner
    {
        require(_data.timeFinished > 0, "Staking must be complete");

        uint256 amountToWithdraw = _totalRewards;
        _totalRewards = 0;

        stakingToken.safeTransfer(msg.sender, amountToWithdraw);
    }

    /**
     * @dev Closes reward period
     *
     * @notice This is a one-way function. Once staking is closed, it
     * cannot be re-enabled. Use cautiously.
     */
    function closeRewards() external payable onlyOwner
    {
        require(_data.isActive == 1, "Contract already inactive");

        _data.isActive = 2;
        _data.timeFinished = uint64(block.timestamp);
        
        emit StakingEnded(block.timestamp);
    }

    /**
     * @dev Enables staking
     */
    function enableStaking() external payable onlyOwner
    {
        require(_data.isActive == 2, "Staking already active");
        
        _data.isActive = 1;

        emit StakingEnabled();
    }

    /**
     * @dev Allows the owner to submit a stake on behalf of other
     *
     * @param account the user account to deposit on behalf of
     * @param amount the amount of tokens to deposit on behalf of user
     * @param timestamp the timestamp of the user's latest deposit
     * @param lock the lock id of the user's existing stake
     *
     * @notice This is to accommodate the token migration so that users
     * will have their existing stakes transition seamlessly to a new staking contract.
     */
    function stakeOnBehalfOf(address account, uint256 amount, uint32 timestamp, uint8 lock, uint256 paid) external payable onlyOwner
    {
        require(timestamp <= block.timestamp, "Cannot stake with future date");
        require(lock > 0 && lock < 4, "Lock must be 1, 2, or 3");
        require(amount > 0, "Amount cannot be 0");

        _deposits[account] = UserDeposit({
            lock: lock,
            timestamp: timestamp,
            staked: amount,
            paid: paid
        });

        _totalSupply += amount;
    }

    /**
     * @dev Allows the owner to submit a list of stakers on behalf of all
     *
     * @param deposits a list of structs to add stakers to contract
     */
    function stakeOnBehalfOfAll(UserDepositByOwner[] calldata deposits) external payable onlyOwner
    {
        for (uint i = 0; i < deposits.length;) {
            _deposits[deposits[i].account] = UserDeposit({
                lock: deposits[i].lock,
                timestamp: deposits[i].timestamp,
                staked: deposits[i].staked,
                paid: deposits[i].paid
            });

            _totalSupply += deposits[i].staked;

            unchecked { ++i; }
        }
    }

    /**
     * @dev Allows the owner to reset a user's paid amount
     * 
     * @param account the user account to reset
     * 
     * @notice Since the contract calculates on-the-fly, we need to track user
     * paid amount. This will reset that value to 0.
     */
    function ownerResetPaid(address account) external payable onlyOwner
    {
        UserDeposit storage userDeposit = _deposits[account];
        userDeposit.paid = 0;
    }

    // ===== EVENTS ===== //

    event StakingFunded(uint256 amount);
    event StakingEnabled();
    event StakingEnded(uint256 timestamp);
    event RewardsClaimed(uint256 amount);
    event Deposited(address indexed account, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);
    event MinimumUpdated(uint256 newMinimum);
}