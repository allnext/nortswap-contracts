// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/*
 * NortTokenFinance
 * App:             https://token.nort.app.br
 * Twitter:         https://twitter.com/Nort83973702
 * Telegram:        https://t.me/joinchat/6FpT_cW2fc5hODEx
 * Announcements:   https://t.me/joinchat/6FpT_cW2fc5hODEx
 * GitHub:          https://github.com/allnext
 */

import "./presets/SafeMath.sol";
import "./presets/IBEP20.sol";
import "./SafeBEP20.sol";
import "./presets/Ownable.sol";

contract BEP20RewardVault is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardLockedUp; // Reward locked up.
        uint256 nextHarvestUntil; // When can the user harvest again.
        uint256 lastInteraction; // Last time when user deposited or claimed rewards, renewing the lock
        address indicator; // optional indicator - will receive a amount of reward based on his client total token locked
    }

    struct IndicatorInfo {
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 amount; // amount of client tokens locked
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Rewards to distribute per block.
        uint256 lastRewardBlock; // Last block number that Rewards distribution occurs.
        uint256 accRewardTokenPerShare; // Accumulated Rewards per share, times 1e30. See below.
        uint256 harvestInterval; // Harvest interval in seconds
        uint256 totalLp; // Total token in Pool
        uint256 lockupDuration; // Amount of time the participant will be locked in the pool after depositing or claiming rewards
    }

    // The stake token
    IBEP20 public stakeToken;
    // The reward token
    IBEP20 public rewardToken;

    // Reward tokens per block.
    uint256 public rewardPerBlock;

    // Reward tokens to indicator per block.
    uint256 public rewardIndicatorPerBlock;

    // Keep track of number of tokens staked in case the contract earns reflect fees
    uint256 public totalStaked = 0;

    // Bonus muliplier for early banana makers.
    uint256 public BONUS_MULTIPLIER;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;
    // Info of each indicator rewards and clients.
    mapping(address => IndicatorInfo) public indicatorInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 private totalAllocPoint = 0;
    // The block number when Reward mining starts.
    uint256 public startBlock;
    // The block number when mining ends.
    uint256 public bonusEndBlock;
    // Max harvest interval: 30 days
    uint256 public constant MAXIMUM_HARVEST_INTERVAL = 30 days;

    event Deposit(address indexed user, uint256 amount);
    event DepositRewards(uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event EmergencyRewardWithdraw(address indexed user, uint256 amount);
    event SkimStakeTokenFees(address indexed user, uint256 amount);

    constructor(
        IBEP20 _stakeToken,
        IBEP20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _rewardIndicatorPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _multiplier,
        uint256 _lockupDuration,
        uint256 _harvestInterval
    ) {
        stakeToken = _stakeToken;
        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        rewardIndicatorPerBlock = _rewardIndicatorPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        BONUS_MULTIPLIER = _multiplier;
        // staking pool
        poolInfo.push(
            PoolInfo({
                lpToken: _stakeToken,
                allocPoint: 1000,
                lastRewardBlock: startBlock,
                accRewardTokenPerShare: 0,
                harvestInterval: _harvestInterval,
                totalLp: 0,
                lockupDuration: _lockupDuration
            })
        );
        totalAllocPoint = 1000;
    }

    //Update bonus multiplyer - only owner
    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER);
        }
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[_user];
        IndicatorInfo storage indicator = indicatorInfo[_user];
        uint256 accRewardTokenPerShare = pool.accRewardTokenPerShare;
        uint256 accRewardTokenPerShareIndicator = getIndicatorRewardPerShare(
            _user
        );
        if (block.number > pool.lastRewardBlock && totalStaked != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 tokenReward = multiplier
                .mul(rewardPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            uint256 tokenRewardIndicator = multiplier
                .mul(rewardIndicatorPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accRewardTokenPerShare = accRewardTokenPerShare.add(
                tokenReward.mul(1e30).div(totalStaked)
            );
            if (indicator.amount > 0) {
                accRewardTokenPerShareIndicator = accRewardTokenPerShareIndicator
                    .add(tokenRewardIndicator.mul(1e30).div(indicator.amount));
            }
        }
        return
            user
                .amount
                .mul(accRewardTokenPerShare)
                .div(1e30)
                .sub(user.rewardDebt)
                .add(
                    indicator
                        .amount
                        .mul(accRewardTokenPerShareIndicator)
                        .div(1e30)
                        .sub(indicator.rewardDebt)
                );
    }

    // View function to see when user will be unlocked from pool
    function userLockedUntil(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        PoolInfo storage pool = poolInfo[0];

        return user.lastInteraction + pool.lockupDuration;
    }

    // View function to see if user can harvest Solar.
    function canHarvest(address _user) public view returns (bool) {
        UserInfo storage user = userInfo[_user];
        return
            block.number >= startBlock &&
            block.timestamp >= user.nextHarvestUntil;
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        if (totalStaked == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier
            .mul(rewardPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);
        pool.accRewardTokenPerShare = pool.accRewardTokenPerShare.add(
            tokenReward.mul(1e30).div(totalStaked)
        );
        pool.lastRewardBlock = block.number;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /// Deposit staking token into the contract to earn rewards.
    /// @dev Since this contract needs to be supplied with rewards we are
    ///  sending the balance of the contract if the pending rewards are higher
    /// @param _amount The amount of staking tokens to deposit
    /// @param _indicator The indicator address (optional)
    function deposit(uint256 _amount, address _indicator) public {
        require(
            _indicator != msg.sender,
            "Deposit: indicator cannot be sender"
        );
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        uint256 finalDepositAmount = 0;
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accRewardTokenPerShare)
                .div(1e30)
                .sub(user.rewardDebt);
            if (pending > 0) {
                uint256 currentRewardBalance = rewardBalance();
                if (currentRewardBalance > 0) {
                    if (pending > currentRewardBalance) {
                        safeTransferReward(
                            address(msg.sender),
                            currentRewardBalance
                        );
                    } else {
                        safeTransferReward(address(msg.sender), pending);
                    }
                }
            }
        }
        if (_amount > 0) {
            user.lastInteraction = block.timestamp;
            user.nextHarvestUntil = block.timestamp.add(pool.harvestInterval);
            if (user.indicator == address(0) && _indicator != address(0)) {
                user.indicator = _indicator; //set indicator only if not has a indicator
                indicatorInfo[_indicator].amount = indicatorInfo[_indicator]
                    .amount
                    .add(_amount); //create indicator client  list with client amount
            } else if (_indicator != address(0)) {
                indicatorInfo[_indicator].amount = indicatorInfo[_indicator]
                    .amount
                    .add(_amount); //create indicator client  list with client amount
            }
            uint256 preStakeBalance = totalStakeTokenBalance();
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            finalDepositAmount = totalStakeTokenBalance().sub(preStakeBalance);
            user.amount = user.amount.add(finalDepositAmount);
            totalStaked = totalStaked.add(finalDepositAmount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardTokenPerShare).div(
            1e30
        );

        emit Deposit(msg.sender, finalDepositAmount);
    }

    /// Returns pending indicator rewards per share
    /// @param _indicator The indicator address
    function getIndicatorRewardPerShare(address _indicator)
        public
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[0];
        IndicatorInfo storage indicator = indicatorInfo[_indicator];
        uint256 accRewardTokenPerShareIndicator = 0;
        if (indicator.amount > 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 tokenRewardIndicator = multiplier
                .mul(rewardIndicatorPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);

            accRewardTokenPerShareIndicator = tokenRewardIndicator
                .mul(1e30)
                .div(indicator.amount);
        }
        return accRewardTokenPerShareIndicator;
    }

    /// Returns pending indicator rewards
    /// @param _indicator The indicator address
    function getIndicatorRewards(address _indicator)
        public
        view
        returns (uint256)
    {
        IndicatorInfo storage indicator = indicatorInfo[_indicator];
        uint256 pendingIndicator = 0;
        uint256 accRewardTokenPerShareIndicator = getIndicatorRewardPerShare(
            _indicator
        );

        if (indicator.amount > 0) {
            pendingIndicator = indicator
                .amount
                .mul(accRewardTokenPerShareIndicator)
                .div(1e30)
                .sub(indicator.rewardDebt);
        }

        return pendingIndicator;
    }

    /// Withdraw rewards and/or staked tokens. Pass a 0 amount to withdraw only rewards
    /// @param _amount The amount of staking tokens to withdraw
    function withdraw(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        //Cannot withdraw before lock time
        require(
            (block.timestamp > user.lastInteraction + pool.lockupDuration &&
                _amount > 0) ||
                _amount == 0 ||
                block.number >= bonusEndBlock,
            "Withdraw: you cannot withdraw yet"
        ); // only rewards

        updatePool(0);

        uint256 pendingIndicator = getIndicatorRewards(msg.sender);
        uint256 currentRewardBalance = rewardBalance();
        if (pendingIndicator > 0) {
            if (currentRewardBalance > 0) {
                if (pendingIndicator > currentRewardBalance) {
                    safeTransferReward(
                        address(msg.sender),
                        currentRewardBalance
                    );
                } else {
                    safeTransferReward(address(msg.sender), pendingIndicator);
                }
            }
        }

        uint256 pending = user
            .amount
            .mul(pool.accRewardTokenPerShare)
            .div(1e30)
            .sub(user.rewardDebt);
        if (pending > 0) {
            pendingIndicator = getIndicatorRewards(user.indicator);
            if (pendingIndicator > 0) {
                currentRewardBalance = rewardBalance();
                if (currentRewardBalance > 0) {
                    if (pendingIndicator > currentRewardBalance) {
                        safeTransferReward(
                            address(msg.sender),
                            currentRewardBalance
                        );
                    } else {
                        safeTransferReward(
                            address(msg.sender),
                            pendingIndicator
                        );
                    }
                }
            }
            if (currentRewardBalance > 0) {
                if (pending > currentRewardBalance) {
                    safeTransferReward(
                        address(msg.sender),
                        currentRewardBalance
                    );
                } else {
                    safeTransferReward(address(msg.sender), pending);
                }
            }
        }
        if (_amount > 0) {
            user.lastInteraction = block.timestamp;
            user.nextHarvestUntil = block.timestamp.add(pool.harvestInterval);
            if (indicatorInfo[user.indicator].amount >= _amount) {
                indicatorInfo[user.indicator].amount = indicatorInfo[
                    user.indicator
                ].amount.sub(_amount);
            }
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            totalStaked = totalStaked.sub(_amount);
        }

        user.rewardDebt = user.amount.mul(pool.accRewardTokenPerShare).div(
            1e30
        );
        if (user.indicator != address(0)) {
            uint256 accRewardTokenPerShareIndicator = getIndicatorRewardPerShare(
                    user.indicator
                );

            indicatorInfo[user.indicator].rewardDebt = indicatorInfo[
                user.indicator
            ].amount.mul(accRewardTokenPerShareIndicator).div(1e30);
        }

        emit Withdraw(msg.sender, _amount);
    }

    /// Obtain the reward balance of this contract
    /// @return wei balace of conract
    function rewardBalance() public view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

    // Deposit Rewards into contract
    function depositRewards(uint256 _amount) external {
        require(_amount > 0, "Deposit value must be greater than 0.");
        rewardToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        emit DepositRewards(_amount);
    }

    /// @param _to address to send reward token to
    /// @param _amount value of reward token to transfer
    function safeTransferReward(address _to, uint256 _amount) internal {
        rewardToken.safeTransfer(_to, _amount);
    }

    /* Admin Functions */

    /// @param _rewardIndicatorPerBlock The amount of reward tokens to be given per block
    function setIndicatorBonus(uint256 _rewardIndicatorPerBlock)
        external
        onlyOwner
    {
        rewardIndicatorPerBlock = _rewardIndicatorPerBlock;
    }

    /// @param _rewardPerBlock The amount of reward tokens to be given per block
    function setRewardPerBlock(uint256 _rewardPerBlock) external onlyOwner {
        rewardPerBlock = _rewardPerBlock;
    }

    /// @param  _bonusEndBlock The block when rewards will end
    function setBonusEndBlock(uint256 _bonusEndBlock) external onlyOwner {
        require(
            _bonusEndBlock > bonusEndBlock,
            "new bonus end block must be greater than current"
        );
        bonusEndBlock = _bonusEndBlock;
    }

    /// @dev Obtain the stake token fees (if any) earned by reflect token
    function getStakeTokenFeeBalance() public view returns (uint256) {
        return totalStakeTokenBalance().sub(totalStaked);
    }

    /// @dev Obtain the stake balance of this contract
    /// @return wei balace of contract
    function totalStakeTokenBalance() public view returns (uint256) {
        // Return BEO20 balance
        return stakeToken.balanceOf(address(this));
    }

    /// @dev Remove excess stake tokens earned by reflect fees
    function skimStakeTokenFees() external onlyOwner {
        uint256 stakeTokenFeeBalance = getStakeTokenFeeBalance();
        stakeToken.safeTransfer(msg.sender, stakeTokenFeeBalance);
        emit SkimStakeTokenFees(msg.sender, stakeTokenFeeBalance);
    }

    /* Emergency Functions */

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        require(_amount <= rewardBalance(), "not enough rewards");
        // Withdraw rewards
        safeTransferReward(address(msg.sender), _amount);
        emit EmergencyRewardWithdraw(msg.sender, _amount);
    }
}
