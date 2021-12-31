// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { VotingEscrow } from "./VotingEscrow.sol";

interface CRV20
{
	function future_epoch_time_write() external returns (uint256);
	function rate() external view returns (uint256);
}

interface Controller
{
	function period() external view returns (int128);
	function period_write() external returns (int128);
	function period_timestamp(int128 _p) external view returns (uint256);
	function gauge_relative_weight(address _addr, uint256 _time) external view returns (uint256);
	function voting_escrow() external view returns (address);
	function checkpoint() external;
	function checkpoint_gauge(address _addr) external;
}

interface Minter
{
	function token() external view returns (address);
	function controller() external view returns (address);
	function minted(address _user, address _gauge) external view returns (uint256);
}

contract LiquidityGaugeV3 is IERC20, ReentrancyGuard
{
	using Address for address;
	using SafeERC20 for IERC20;

	event Deposit(address indexed _provider, uint256 _value);
	event Withdraw(address indexed _provider, uint256 _value);
	event UpdateLiquidityLimit(address user, uint256 original_balance, uint256 _original_supply, uint256 _working_balance, uint256 _working_supply);
	event CommitOwnership(address _admin);
	event ApplyOwnership(address _admin);
	event Transfer(address indexed _from, address indexed _to, uint256 _value);
	event Approval(address indexed _owner, address indexed _spender, uint256 _value);

	uint256 constant MAX_REWARDS = 8;
	uint256 constant TOKENLESS_PRODUCTION = 40;
	uint256 constant WEEK = 1 weeks;
	uint256 constant CLAIM_FREQUENCY = 1 hours;

	address public minter;
	address public crv_token;
	address public lp_token;
	address public controller;
	address public voting_escrow;
	uint256 public future_epoch_time;

	mapping(address => uint256) public override balanceOf;
	uint256 public override totalSupply;
	mapping(address => mapping(address => uint256)) public override allowance;

	string public name;
	string public symbol;

	mapping(address => uint256) public working_balances;
	uint256 public working_supply;

	// The goal is to be able to calculate ∫(rate * balance / totalSupply dt) from 0 till checkpoint
	// All values are kept in units of being multiplied by 1e18
	int128 public period;
	mapping(int128 => uint256) public period_timestamp;

	// 1e18 * ∫(rate(t) / totalSupply(t) dt) from 0 till checkpoint
	mapping(int128 => uint256) public integrate_inv_supply; // bump epoch when rate() changes

	// 1e18 * ∫(rate(t) / totalSupply(t) dt) from (last_action) till checkpoint
	mapping(address => uint256) public integrate_inv_supply_of;
	mapping(address => uint256) public integrate_checkpoint_of;

	// ∫(balance * rate(t) / totalSupply(t) dt) from 0 till checkpoint
	// Units: rate * t = already number of coins per address to issue
	mapping(address => uint256) public integrate_fraction;

	uint256 public inflation_rate;

	// For tracking external rewards
	uint256 reward_data;
	address[MAX_REWARDS] public reward_tokens;

	// deposit / withdraw / claim
	bytes32 reward_sigs;

	// claimant -> default reward receiver
	mapping(address => address) public rewards_receiver;

	// reward token -> integral
	mapping(address => uint256) public reward_integral;

	// reward token -> claiming address -> integral
	mapping(address => mapping(address => uint256)) public reward_integral_for;

	// user -> [uint128 claimable amount][uint128 claimed amount]
	mapping(address => mapping(address => uint256)) claim_data;

	address public admin;
	address public future_admin; // Can and will be a smart contract
	bool public is_killed;

	/*
	@notice Contract constructor
	@param _lp_token Liquidity Pool contract address
	@param _minter Minter contract address
	@param _admin Admin who can kill the gauge
	*/
	constructor(address _lp_token, address _minter, address _admin) public
	{
		string memory _symbol = ERC20(_lp_token).symbol();
		name = string(abi.encodePacked("Curve.fi ", symbol, " Gauge Deposit"));
		symbol = string(abi.encodePacked(_symbol, "-gauge"));

		address _crv_token = Minter(_minter).token();
		address _controller = Minter(_minter).controller();

		lp_token = _lp_token;
		minter = _minter;
		admin = _admin;
		crv_token = _crv_token;
		controller = _controller;
		voting_escrow = Controller(_controller).voting_escrow();

		period_timestamp[0] = block.timestamp;
		inflation_rate = CRV20(_crv_token).rate();
		future_epoch_time = CRV20(_crv_token).future_epoch_time_write();
	}

	/*
	@notice Get the number of decimals for this token
	@dev Implemented as a view method to reduce gas costs
	@return uint256 decimal places
	*/
	function decimals() external pure returns (uint256)
	{
		return 18;
	}

	function integrate_checkpoint() external view returns (uint256)
	{
		return period_timestamp[period];
	}

	/*
	@notice Calculate limits which depend on the amount of CRV token per-user.
	    Effectively it calculates working balances to apply amplification
	    of CRV production by CRV
	@param addr User address
	@param l User's amount of liquidity (LP tokens)
	@param L Total amount of liquidity (LP tokens)
	*/
	function _update_liquidity_limit(address _addr, uint256 _l, uint256 _L) internal
	{
		// To be called after totalSupply is updated
		address _voting_escrow = voting_escrow;
		uint256 _voting_balance = ERC20(_voting_escrow).balanceOf(_addr);
		uint256 _voting_total = ERC20(_voting_escrow).totalSupply();

		uint256 _lim = _l * TOKENLESS_PRODUCTION / 100;
		if (_voting_total > 0) {
			_lim += _L * _voting_balance / _voting_total * (100 - TOKENLESS_PRODUCTION) / 100;
		}

		if (_l < _lim) _lim = _l;
		uint256 _old_bal = working_balances[_addr];
		working_balances[_addr] = _lim;
		uint256 _working_supply = working_supply + _lim - _old_bal;
		working_supply = _working_supply;

		emit UpdateLiquidityLimit(_addr, _l, _L, _lim, _working_supply);
	}

	/*
	@notice Claim pending rewards and checkpoint rewards for a user
	*/
	function _checkpoint_rewards(address _user, uint256 _total_supply, bool _claim, address _receiver) internal
	{
		// load reward tokens and integrals into memory
		uint256[MAX_REWARDS] memory _reward_integrals;
		for (uint256 _i = 0; _i < MAX_REWARDS; _i++) {
			address _token = reward_tokens[_i];
			if (_token == address(0)) {
				break;
			}
			_reward_integrals[_i] = reward_integral[_token];
		}

		{
			uint256 _reward_data = reward_data;
			if (_total_supply != 0 && _reward_data != 0 && block.timestamp > (_reward_data >> 160) + CLAIM_FREQUENCY) {
				// track balances prior to claiming
				uint256[MAX_REWARDS] memory _reward_balances;
				for (uint256 _i = 0; _i < MAX_REWARDS; _i++) {
					address _token = reward_tokens[_i];
					if (_token == address(0)) {
						break;
					}
					_reward_balances[_i] = IERC20(_token).balanceOf(address(this));
				}

				// claim from reward contract
				address _reward_contract = address(_reward_data % 2**160);

				{
				(bool _success, bytes memory _result) = _reward_contract.call(abi.encodeWithSelector(bytes4(bytes32(uint256(reward_sigs) << 64))));
				require(_success, string(_result));
				}
				reward_data = uint256(_reward_contract) + block.timestamp << 160;

				// get balances after claim and calculate new reward integrals
				for (uint256 _i = 0; _i < MAX_REWARDS; _i++) {
					address _token = reward_tokens[_i];
					if (_token == address(0)) {
						break;
					}
					uint256 _dI = 10**18 * (IERC20(_token).balanceOf(address(this)) - _reward_balances[_i]) / _total_supply;
					if (_dI > 0) {
						_reward_integrals[_i] += _dI;
						reward_integral[_token] = _reward_integrals[_i];
					}
				}
			}
		}

		if (_user != address(0)) {

			address __receiver = _receiver;
			if (_claim && __receiver == address(0)) {
				// if receiver is not explicitly declared, check for default receiver
				__receiver = rewards_receiver[_user];
				if (__receiver == address(0)) {
					// direct claims to user if no default receiver is set
					__receiver = _user;
				}
			}

			// calculate new user reward integral and transfer any owed rewards
			uint256 _user_balance = balanceOf[_user];
			for (uint256 _i = 0; _i < MAX_REWARDS; _i++) {
				address _token = reward_tokens[_i];
				if (_token == address(0)) {
					break;
				}

				uint256 _new_claimable = 0;
				{
					uint256 _integral = _reward_integrals[_i];
					uint256 _integral_for = reward_integral_for[_token][_user];
					if (_integral_for < _integral) {
						reward_integral_for[_token][_user] = _integral;
						_new_claimable = _user_balance * (_integral - _integral_for) / 10**18;
					}
				}

				uint256 _claim_data = claim_data[_user][_token];
				uint256 _total_claimable = (_claim_data >> 128) + _new_claimable;
				if (_total_claimable > 0) {
					uint256 _total_claimed = _claim_data % 2 ** 128;
					if (_claim) {
						IERC20(_token).safeTransfer(__receiver, _total_claimable);
						// update amount claimed (lower order bytes)
						claim_data[_user][_token] = _total_claimed + _total_claimable;
					} else if (_new_claimable > 0) {
						// update total_claimable (higher order bytes)
						claim_data[_user][_token] = _total_claimed + (_total_claimable << 128);
					}
				}
			}
		}
	}

	/*
	@notice Checkpoint for a user
	@param addr User address
	*/
	function _checkpoint(address _addr) internal
	{
		int128 _period = period;
		uint256 _period_time = period_timestamp[_period];
		uint256 _integrate_inv_supply = integrate_inv_supply[_period];
		uint256 _rate = inflation_rate;
		uint256 _new_rate = _rate;
		uint256 _prev_future_epoch = future_epoch_time;
		if (_prev_future_epoch >= _period_time) {
			address _token = crv_token;
			future_epoch_time = CRV20(_token).future_epoch_time_write();
			_new_rate = CRV20(_token).rate();
			inflation_rate = _new_rate;
		}

		if (is_killed) {
			// Stop distributing inflation as soon as killed
			_rate = 0;
		}

		// Update integral of 1/supply
		if (block.timestamp > _period_time) {
			uint256 _working_supply = working_supply;
			address _controller = controller;
			Controller(_controller).checkpoint_gauge(address(this));
			uint256 _prev_week_time = _period_time;
			uint256 _week_time = (_period_time + WEEK) / WEEK * WEEK;
			if (_week_time > block.timestamp) _week_time = block.timestamp;

			for (uint256 _i = 0; _i < 500; _i++) {
				uint256 _dt = _week_time - _prev_week_time;
				uint256 _w = Controller(_controller).gauge_relative_weight(address(this), _prev_week_time / WEEK * WEEK);

				if (_working_supply > 0) {
					if (_prev_future_epoch >= _prev_week_time && _prev_future_epoch < _week_time) {
						// If we went across one or multiple epochs, apply the rate
						// of the first epoch until it ends, and then the rate of
						// the last epoch.
						// If more than one epoch is crossed - the gauge gets less,
						// but that'd meen it wasn't called for more than 1 year
						_integrate_inv_supply += _rate * _w * (_prev_future_epoch - _prev_week_time) / _working_supply;
						_rate = _new_rate;
						_integrate_inv_supply += _rate * _w * (_week_time - _prev_future_epoch) / _working_supply;
					} else {
						_integrate_inv_supply += _rate * _w * _dt / _working_supply;
					}
					// On precisions of the calculation
					// rate ~= 10e18
					// last_weight > 0.01 * 1e18 = 1e16 (if pool weight is 1%)
					// _working_supply ~= TVL * 1e18 ~= 1e26 ($100M for example)
					// The largest loss is at dt = 1
					// Loss is 1e-9 - acceptable
				}

				if (_week_time == block.timestamp) {
					break;
				}
				_prev_week_time = _week_time;
				_week_time = _week_time + WEEK;
				if (_week_time > block.timestamp) _week_time = block.timestamp;
			}
		}

		_period += 1;
		period = _period;
		period_timestamp[_period] = block.timestamp;
		integrate_inv_supply[_period] = _integrate_inv_supply;

		// Update user-specific integrals
		uint256 _working_balance = working_balances[_addr];
		integrate_fraction[_addr] += _working_balance * (_integrate_inv_supply - integrate_inv_supply_of[_addr]) / 10 ** 18;
		integrate_inv_supply_of[_addr] = _integrate_inv_supply;
		integrate_checkpoint_of[_addr] = block.timestamp;
	}

	/*
	@notice Record a checkpoint for `addr`
	@param addr User address
	@return bool success
	*/
	function user_checkpoint(address _addr) external returns (bool)
	{
		require(msg.sender == _addr || msg.sender == minter); // dev: unauthorized
		_checkpoint(_addr);
		_update_liquidity_limit(_addr, balanceOf[_addr], totalSupply);
		return true;
	}

	/*
	@notice Get the number of claimable tokens per user
	@dev This function should be manually changed to "view" in the ABI
	@return uint256 number of claimable tokens per user
	*/
	function claimable_tokens(address _addr) external returns (uint256)
	{
		_checkpoint(_addr);
		return integrate_fraction[_addr] - Minter(minter).minted(_addr, address(this));
	}

	/*
	@notice Address of the reward contract providing non-CRV incentives for this gauge
	@dev Returns `ZERO_ADDRESS` if there is no reward contract active
	*/
	function reward_contract() external view returns (address)
	{
		return address(reward_data % 2**160);
	}

	/*
	@notice Epoch timestamp of the last call to claim from `reward_contract`
	@dev Rewards are claimed at most once per hour in order to reduce gas costs
	*/
	function last_claim() external view returns (uint256)
	{
		return reward_data >> 160;
	}

	function claimed_reward(address _addr, address _token) external view returns (uint256)
	{
		/*
		@notice Get the number of already-claimed reward tokens for a user
		@param _addr Account to get reward amount for
		@param _token Token to get reward amount for
		@return uint256 Total amount of `_token` already claimed by `_addr`
		*/
		return claim_data[_addr][_token] % 2**128;
	}

	/*
	@notice Get the number of claimable reward tokens for a user
	@dev This call does not consider pending claimable amount in `reward_contract`.
	 Off-chain callers should instead use `claimable_rewards_write` as a
	 view method.
	@param _addr Account to get reward amount for
	@param _token Token to get reward amount for
	@return uint256 Claimable reward token amount
	*/
	function claimable_reward(address _addr, address _token) external view returns (uint256)
	{
		return claim_data[_addr][_token] >> 128;
	}

	/*
	@notice Get the number of claimable reward tokens for a user
	@dev This function should be manually changed to "view" in the ABI
	 Calling it via a transaction will claim available reward tokens
	@param _addr Account to get reward amount for
	@param _token Token to get reward amount for
	@return uint256 Claimable reward token amount
	*/
	function claimable_reward_write(address _addr, address _token) external nonReentrant returns (uint256)
	{
		if (reward_tokens[0] != address(0)) {
			_checkpoint_rewards(_addr, totalSupply, false, address(0));
		}
		return claim_data[_addr][_token] >> 128;
	}

	/*
	@notice Set the default reward receiver for the caller.
	@dev When set to ZERO_ADDRESS, rewards are sent to the caller
	@param _receiver Receiver address for any rewards claimed via `claim_rewards`
	*/
	function set_rewards_receiver(address _receiver) external
	{
		rewards_receiver[msg.sender] = _receiver;
	}

	/*
	@notice Claim available reward tokens for `_addr`
	@param _addr Address to claim for
	@param _receiver Address to transfer rewards to - if set to
		     ZERO_ADDRESS, uses the default reward receiver
		     for the caller
	*/
	function claim_rewards() external nonReentrant
	{
		claim_rewards(msg.sender, address(0));
	}
	function claim_rewards(address _addr) external nonReentrant
	{
		claim_rewards(_addr, address(0));
	}
	function claim_rewards(address _addr, address _receiver) public nonReentrant
	{
		if (_receiver != address(0)) {
			require(_addr == msg.sender); // dev: cannot redirect when claiming for another user
		}
		_checkpoint_rewards(_addr, totalSupply, true, _receiver);
	}

	/*
	@notice Kick `addr` for abusing their boost
	@dev Only if either they had another voting event, or their voting escrow lock expired
	@param addr Address to kick
	*/
	function kick(address _addr) external
	{
		address _voting_escrow = voting_escrow;
		uint256 _t_last = integrate_checkpoint_of[_addr];
		uint256 _t_ve = VotingEscrow(_voting_escrow).user_point_history__ts(_addr, VotingEscrow(_voting_escrow).user_point_epoch(_addr));
		uint256 _balance = balanceOf[_addr];

		require(IERC20(_voting_escrow).balanceOf(_addr) == 0 || _t_ve > _t_last); // dev: kick not allowed
		require(working_balances[_addr] > _balance * TOKENLESS_PRODUCTION / 100); // dev: kick not needed

		_checkpoint(_addr);
		_update_liquidity_limit(_addr, balanceOf[_addr], totalSupply);
	}

	/*
	@notice Deposit `_value` LP tokens
	@dev Depositting also claims pending reward tokens
	@param _value Number of tokens to deposit
	@param _addr Address to deposit for
	*/
	function deposit(uint256 _value) external
	{
		deposit(_value, msg.sender, false);
	}
	function deposit(uint256 _value, address _addr) external
	{
		deposit(_value, _addr, false);
	}
	function deposit(uint256 _value, address _addr, bool _claim_rewards) public nonReentrant
	{
		_checkpoint(_addr);

		if (_value != 0) {
			bool _is_rewards = reward_tokens[0] != address(0);
			uint256 _total_supply = totalSupply;
			if (_is_rewards) {
				_checkpoint_rewards(_addr, _total_supply, _claim_rewards, address(0));
			}

			_total_supply += _value;
			uint256 _new_balance = balanceOf[_addr] + _value;
			balanceOf[_addr] = _new_balance;
			totalSupply = _total_supply;

			_update_liquidity_limit(_addr, _new_balance, _total_supply);

			IERC20(lp_token).transferFrom(msg.sender, address(this), _value);
			if (_is_rewards) {
				uint256 _reward_data = reward_data;
				if (_reward_data > 0) {
					bytes4 _deposit_sig = bytes4(reward_sigs);
					if (uint32(_deposit_sig) != 0) {
						{
						(bool _success, bytes memory _result) = address(reward_data % 2**160).call(abi.encodeWithSelector(_deposit_sig, _value));
						require(_success, string(_result));
						}
					}
				}
			}
		}

		emit Deposit(_addr, _value);
		emit Transfer(address(0), _addr, _value);
	}

	/*
	@notice Withdraw `_value` LP tokens
	@dev Withdrawing also claims pending reward tokens
	@param _value Number of tokens to withdraw
	*/
	function withdraw(uint256 _value) external
	{
		withdraw(_value, false);
	}
	function withdraw(uint256 _value, bool _claim_rewards) public nonReentrant
	{
		_checkpoint(msg.sender);

		if (_value != 0) {
			bool _is_rewards = reward_tokens[0] != address(0);
			uint256 _total_supply = totalSupply;
			if (_is_rewards) {
				_checkpoint_rewards(msg.sender, _total_supply, _claim_rewards, address(0));
			}

			_total_supply -= _value;
			uint256 _new_balance = balanceOf[msg.sender] - _value;
			balanceOf[msg.sender] = _new_balance;
			totalSupply = _total_supply;

			_update_liquidity_limit(msg.sender, _new_balance, _total_supply);

			if (_is_rewards) {
				uint256 _reward_data = reward_data;
				if (_reward_data > 0) {
					bytes4 _withdraw_sig = bytes4(bytes32(uint256(reward_sigs) << 32));
					if (uint32(_withdraw_sig) != 0) {
						{
						(bool _success, bytes memory _result) = address(reward_data % 2**160).call(abi.encodeWithSelector(_withdraw_sig, _value));
						require(_success, string(_result));
						}
					}
				}
			}
			IERC20(lp_token).transfer(msg.sender, _value);
		}

		emit Withdraw(msg.sender, _value);
		emit Transfer(msg.sender, address(0), _value);
	}

	function _transfer(address _from, address _to, uint256 _value) internal
	{
		_checkpoint(_from);
		_checkpoint(_to);

		if (_value != 0) {
			uint256 _total_supply = totalSupply;
			bool _is_rewards = reward_tokens[0] != address(0);
			if (_is_rewards) {
				_checkpoint_rewards(_from, _total_supply, false, address(0));
			}
			uint256 _new_balance = balanceOf[_from] - _value;
			balanceOf[_from] = _new_balance;
			_update_liquidity_limit(_from, _new_balance, _total_supply);

			if (_is_rewards) {
				_checkpoint_rewards(_to, _total_supply, false, address(0));
			}
			_new_balance = balanceOf[_to] + _value;
			balanceOf[_to] = _new_balance;
			_update_liquidity_limit(_to, _new_balance, _total_supply);
		}

		emit Transfer(_from, _to, _value);
	}

	/*
	@notice Transfer token for a specified address
	@dev Transferring claims pending reward tokens for the sender and receiver
	@param _to The address to transfer to.
	@param _value The amount to be transferred.
	*/
	function transfer(address _to, uint256 _value) external override nonReentrant returns (bool)
	{
		_transfer(msg.sender, _to, _value);

		return true;
	}

	function transferFrom(address _from, address _to, uint256 _value) external override nonReentrant returns (bool)
	{
		/*
		@notice Transfer tokens from one address to another.
		@dev Transferring claims pending reward tokens for the sender and receiver
		@param _from address The address which you want to send tokens from
		@param _to address The address which you want to transfer to
		@param _value uint256 the amount of tokens to be transferred
		*/
		uint256 _allowance = allowance[_from][msg.sender];
		if (_allowance != uint256(-1)) {
			allowance[_from][msg.sender] = _allowance - _value;
		}

		_transfer(_from, _to, _value);

		return true;
	}

	/*
	@notice Approve the passed address to transfer the specified amount of
	    tokens on behalf of msg.sender
	@dev Beware that changing an allowance via this method brings the risk
	 that someone may use both the old and new allowance by unfortunate
	 transaction ordering. This may be mitigated with the use of
	 {incraseAllowance} and {decreaseAllowance}.
	 https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
	@param _spender The address which will transfer the funds
	@param _value The amount of tokens that may be transferred
	@return bool success
	*/
	function approve(address _spender, uint256 _value) external override returns (bool)
	{
		allowance[msg.sender][_spender] = _value;
		emit Approval(msg.sender, _spender, _value);

		return true;
	}

	/*
	@notice Increase the allowance granted to `_spender` by the caller
	@dev This is alternative to {approve} that can be used as a mitigation for
	 the potential race condition
	@param _spender The address which will transfer the funds
	@param _added_value The amount of to increase the allowance
	@return bool success
	*/
	function increaseAllowance(address _spender, uint256 _added_value) external returns (bool)
	{
		uint256 _allowance = allowance[msg.sender][_spender] + _added_value;
		allowance[msg.sender][_spender] = _allowance;

		emit Approval(msg.sender, _spender, _allowance);

		return true;
	}

	/*
	@notice Decrease the allowance granted to `_spender` by the caller
	@dev This is alternative to {approve} that can be used as a mitigation for
	 the potential race condition
	@param _spender The address which will transfer the funds
	@param _subtracted_value The amount of to decrease the allowance
	@return bool success
	*/
	function decreaseAllowance(address _spender, uint256 _subtracted_value) external returns (bool)
	{
		uint256 _allowance = allowance[msg.sender][_spender] - _subtracted_value;
		allowance[msg.sender][_spender] = _allowance;

		emit Approval(msg.sender, _spender, _allowance);

		return true;
	}

	/*
	@notice Set the active reward contract
	@dev A reward contract cannot be set while this contract has no deposits
	@param _reward_contract Reward contract address. Set to ZERO_ADDRESS to
		            disable staking.
	@param _sigs Four byte selectors for staking, withdrawing and claiming,
		 right padded with zero bytes. If the reward contract can
		 be claimed from but does not require staking, the staking
		 and withdraw selectors should be set to 0x00
	@param _reward_tokens List of claimable reward tokens. New reward tokens
		          may be added but they cannot be removed. When calling
		          this function to unset or modify a reward contract,
		          this array must begin with the already-set reward
		          token addresses.
	*/
	function set_rewards(address _reward_contract, bytes32 _sigs, address[MAX_REWARDS] calldata _reward_tokens) external nonReentrant
	{
		require(msg.sender == admin);

		address _lp_token = lp_token;
		address _current_reward_contract = address(reward_data % 2**160);
		uint256 _total_supply = totalSupply;
		if (reward_tokens[0] != address(0)) {
			_checkpoint_rewards(address(0), _total_supply, false, address(0));
		}
		if (_current_reward_contract != address(0)) {
			bytes4 _withdraw_sig = bytes4(bytes32(uint256(_sigs) << 32));
			if (uint32(_withdraw_sig) != 0) {
				if (_total_supply != 0) {
					{
					(bool _success, bytes memory _result) = _current_reward_contract.call(abi.encodeWithSelector(_withdraw_sig, _total_supply));
					require(_success, string(_result));
					}
				}
				IERC20(_lp_token).approve(_current_reward_contract, 0);
			}
		}

		if (_reward_contract != address(0)) {
			require(_reward_tokens[0] != address(0)); // dev: no reward token
			require(_reward_contract.isContract()); // dev: not a contract
			bytes4 _deposit_sig = bytes4(_sigs);
			bytes4 _withdraw_sig = bytes4(bytes32(uint256(_sigs) << 32));

			if (uint32(_deposit_sig) != 0) {
				// need a non-zero total supply to verify the sigs
				require(_total_supply != 0); // dev: zero total supply
				IERC20(lp_token).approve(_reward_contract, uint256(-1));

				// it would be Very Bad if we get the signatures wrong here, so
				// we do a test deposit and withdrawal prior to setting them
				{
				(bool _success, bytes memory _result) = _reward_contract.call(abi.encodeWithSelector(_deposit_sig, _total_supply)); // dev: failed deposit
				require(_success, string(_result));
				}
				require(IERC20(lp_token).balanceOf(address(this)) == 0);
				{
				(bool _success, bytes memory _result) = _reward_contract.call(abi.encodeWithSelector(_withdraw_sig, _total_supply)); // dev: failed withdraw
				require(_success, string(_result));
				}
				require(IERC20(lp_token).balanceOf(address(this)) == _total_supply);

				// deposit and withdraw are good, time to make the actual deposit
				{
				(bool _success, bytes memory _result) = _reward_contract.call(abi.encodeWithSelector(_deposit_sig, _total_supply));
				require(_success, string(_result));
				}
			} else {
				require(uint32(_withdraw_sig) == 0); // dev: withdraw without deposit
			}
		}
		reward_data = uint256(_reward_contract);
		reward_sigs = _sigs;
		for (uint256 _i = 0; _i < MAX_REWARDS; _i++) {
			address _current_token = reward_tokens[_i];
			address _new_token = _reward_tokens[_i];
			if (_current_token != address(0)) {
				require(_current_token == _new_token); // dev: cannot modify existing reward token
			} else if (_new_token != address(0)) {
				// store new reward token
				reward_tokens[_i] = _new_token;
			} else {
				break;
			}
		}

		if (_reward_contract != address(0)) {
			// do an initial checkpoint to verify that claims are working
			_checkpoint_rewards(address(0), _total_supply, false, address(0));
		}
	}

	/*
	@notice Set the killed status for this contract
	@dev When killed, the gauge always yields a rate of 0 and so cannot mint CRV
	@param _is_killed Killed status to set
	*/
	function set_killed(bool _is_killed) external
	{
		require(msg.sender == admin);

		is_killed = _is_killed;
	}

	/*
	@notice Transfer ownership of GaugeController to `addr`
	@param addr Address to have ownership transferred to
	*/
	function commit_transfer_ownership(address _addr) external
	{
		require(msg.sender == admin); // dev: admin only

		future_admin = _addr;
		emit CommitOwnership(_addr);
	}

	/*
	@notice Accept a pending ownership transfer
	*/
	function accept_transfer_ownership() external
	{
		address _admin = future_admin;
		require(msg.sender == _admin);  // dev: future admin only

		admin = _admin;
		emit ApplyOwnership(_admin);
	}
}
