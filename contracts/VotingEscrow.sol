// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/*
@title Voting Escrow
@author Curve Finance
@license MIT
@notice Votes have a weight depending on time, so that users are
        committed to the future of (whatever they are voting for)
@dev Vote weight decays linearly over time. Lock time cannot be
     more than `MAXTIME` (4 years).
*/

// Interface for checking whether address belongs to a whitelisted
// type of a smart wallet.
// When new types are added - the whole contract is changed
// The check() method is modifying to be able to use caching
//for individual wallet addresses

interface SmartWalletChecker
{
	function check(address _addr) external returns (bool);
}

contract VotingEscrow is ReentrancyGuard
{
	// Voting escrow to have time-weighted votes
	// Votes have a weight depending on time, so that users are committed
	// to the future of (whatever they are voting for).
	// The weight in this implementation is linear, and lock cannot be more than maxtime:
	// w ^
	// 1 +        /
	//   |      /
	//   |    /
	//   |  /
	//   |/
	// 0 +--------+------> time
	//       maxtime (4 years?)

	struct Point {
		int128 bias;
		int128 slope; // - dweight / dt
		uint256 ts;
		uint256 blk; // block
	}

	// We cannot really do block numbers per se b/c slope is per time, not per block
	// and per block could be fairly bad b/c Ethereum changes blocktimes.
	// What we can do is to extrapolate ***At functions

	struct LockedBalance {
		int128 amount;
		uint256 end;
	}

	int128 constant DEPOSIT_FOR_TYPE = 0;
	int128 constant CREATE_LOCK_TYPE = 1;
	int128 constant INCREASE_LOCK_AMOUNT = 2;
	int128 constant INCREASE_UNLOCK_TIME = 3;

	event CommitOwnership(address _admin);
	event ApplyOwnership(address _admin);
	event Deposit(address indexed _provider, uint256 _value, uint256 indexed _locktime, int128 _type, uint256 _ts);
	event Withdraw(address indexed _provider, uint256 _value, uint256 _ts);
	event Supply(uint256 _prevSupply, uint256 _supply);

	uint256 constant WEEK = 7 * 86400; // all future times are rounded by week
	uint256 constant MAXTIME = 4 * 365 * 86400; // 4 years
	uint256 constant MULTIPLIER = 10 ** 18;

	address public immutable token;
	uint256 public supply;

	mapping(address => LockedBalance) public locked;

	uint256 public epoch;

	Point[100000000000000000000000000000] public point_history; // epoch -> unsigned point
	mapping(address => Point[1000000000]) public user_point_history; // user -> Point[user_epoch]
	mapping(address => uint256) public user_point_epoch;
	mapping(uint256 => int128) public slope_changes; // time -> signed slope change

	// Aragon's view methods for compatibility
	address public controller;
	bool public transfersEnabled;

	string public name;
	string public symbol;
	string public version;
	uint8 public immutable decimals;

	// Checker for whitelisted (smart contract) wallets which are allowed to deposit
	// The goal is to prevent tokenizing the escrow
	address public future_smart_wallet_checker;
	address public smart_wallet_checker;

	address public admin; // Can and will be a smart contract
	address public future_admin;

	/*
	@notice Contract constructor
	@param _token `ERC20CRV` token address
	@param _name Token name
	@param _symbol Token symbol
	@param _version Contract version - required for Aragon compatibility
	*/
	constructor(address _token, string memory _name, string memory _symbol, string memory _version) public
	{
		admin = msg.sender;
		token = _token;
		point_history[0].blk = block.number;
		point_history[0].ts = block.timestamp;
		controller = msg.sender;
		transfersEnabled = true;

		name = _name;
		symbol = _symbol;
		version = _version;
		decimals = ERC20(_token).decimals();
	}

	/*
	@notice Transfer ownership of VotingEscrow contract to `addr`
	@param addr Address to have ownership transferred to
	*/
	function commit_transfer_ownership(address _addr) external
	{
		require(msg.sender == admin); // dev: admin only
		future_admin = _addr;
		emit CommitOwnership(_addr);
	}

	/*
	@notice Apply ownership transfer
	*/
	function apply_transfer_ownership() external
	{
		require(msg.sender == admin); // dev: admin only
		address _admin = future_admin;
		require(_admin != address(0)); // dev: admin not set
		admin = _admin;
		emit ApplyOwnership(_admin);
	}

	/*
	@notice Set an external contract to check for approved smart contract wallets
	@param addr Address of Smart contract checker
	*/
	function commit_smart_wallet_checker(address _addr) external
	{
		require(msg.sender == admin);
		future_smart_wallet_checker = _addr;
	}

	/*
	@notice Apply setting external contract to check approved smart contract wallets
	*/
	function apply_smart_wallet_checker() external
	{
		require(msg.sender == admin);
		smart_wallet_checker = future_smart_wallet_checker;
	}

	/*
	@notice Check if the call is from a whitelisted smart contract, revert if not
	@param addr Address to be checked
	*/
	function assert_not_contract(address _addr) internal
	{
		if (_addr != tx.origin) {
			address _checker = smart_wallet_checker;
			if (_checker != address(0)) {
				if (SmartWalletChecker(_checker).check(_addr)) {
					return;
				}
			}
			require(false, "Smart contract depositors not allowed");
		}
	}

	/*
	@notice Get the most recently recorded rate of voting power decrease for `addr`
	@param addr Address of the user wallet
	@return Value of the slope
	*/
	function get_last_user_slope(address _addr) external view returns (int128)
	{
		uint256 _uepoch = user_point_epoch[_addr];
		return user_point_history[_addr][_uepoch].slope;
	}

	/*
	@notice Get the timestamp for checkpoint `_idx` for `_addr`
	@param _addr User wallet address
	@param _idx User epoch number
	@return Epoch time of the checkpoint
	*/
	function user_point_history__ts(address _addr, uint256 _idx) external view returns (uint256)
	{
		return user_point_history[_addr][_idx].ts;
	}

	/*
	@notice Get timestamp when `_addr`'s lock finishes
	@param _addr User wallet
	@return Epoch time of the lock end
	*/
	function locked__end(address _addr) external view returns (uint256)
	{
		return locked[_addr].end;
	}

	/*
	@notice Record global and per-user data to checkpoint
	@param addr User's wallet address. No user checkpoint if 0x0
	@param old_locked Pevious locked amount / end lock time for the user
	@param new_locked New locked amount / end lock time for the user
	*/
	function _checkpoint(address _addr, LockedBalance memory _old_locked, LockedBalance memory _new_locked) internal
	{
		Point memory _u_old;
		Point memory _u_new;
		int128 _old_dslope = 0;
		int128 _new_dslope = 0;
		uint256 _epoch = epoch;

		if (_addr != address(0)) {
			// Calculate slopes and biases
			// Kept at zero when they have to
			if (_old_locked.end > block.timestamp && _old_locked.amount > 0) {
				_u_old.slope = _old_locked.amount / int128(MAXTIME);
				_u_old.bias = _u_old.slope * int128(_old_locked.end - block.timestamp);
			}
			if (_new_locked.end > block.timestamp && _new_locked.amount > 0) {
				_u_new.slope = _new_locked.amount / int128(MAXTIME);
				_u_new.bias = _u_new.slope * int128(_new_locked.end - block.timestamp);
			}

			// Read values of scheduled changes in the slope
			// old_locked.end can be in the past and in the future
			// new_locked.end can ONLY by in the FUTURE unless everything expired: than zeros
			_old_dslope = slope_changes[_old_locked.end];
			if (_new_locked.end != 0) {
				if (_new_locked.end == _old_locked.end)
					_new_dslope = _old_dslope;
				else
					_new_dslope = slope_changes[_new_locked.end];
			}
		}

		Point memory _last_point = Point({ bias: 0, slope: 0, ts: block.timestamp, blk: block.number });
		if (_epoch > 0) {
			_last_point = point_history[_epoch];
		}
		uint256 _last_checkpoint = _last_point.ts;
		// initial_last_point is used for extrapolation to calculate block number
		// (approximately, for *At methods) and save them
		// as we cannot figure that out exactly from inside the contract
		Point memory _initial_last_point = _last_point;
		uint256 _block_slope = 0; // dblock/dt
		if (block.timestamp > _last_point.ts) {
			_block_slope = MULTIPLIER * (block.number - _last_point.blk) / (block.timestamp - _last_point.ts);
		}
		// If last point is already recorded in this block, slope=0
		// But that's ok b/c we know the block in such case

		// Go over weeks to fill history and calculate what the current point is
		{
			uint256 _t_i = (_last_checkpoint / WEEK) * WEEK;
			for (uint256 _i = 0; _i < 255; _i++) {
				// Hopefully it won't happen that this won't get used in 5 years!
				// If it does, users will be able to withdraw but vote weight will be broken
				_t_i += WEEK;
				int128 _d_slope = 0;
				if (_t_i > block.timestamp)
					_t_i = block.timestamp;
				else
					_d_slope = slope_changes[_t_i];
				_last_point.bias -= _last_point.slope * int128(_t_i - _last_checkpoint);
				_last_point.slope += _d_slope;
				if (_last_point.bias < 0) { // This can happen
					_last_point.bias = 0;
				}
				if (_last_point.slope < 0) { // This cannot happen - just in case
					_last_point.slope = 0;
				}
				_last_checkpoint = _t_i;
				_last_point.ts = _t_i;
				_last_point.blk = _initial_last_point.blk + _block_slope * (_t_i - _initial_last_point.ts) / MULTIPLIER;
				_epoch += 1;
				if (_t_i == block.timestamp) {
					_last_point.blk = block.number;
					break;
				} else {
					point_history[_epoch] = _last_point;
				}
			}
		}

		epoch = _epoch;
		// Now point_history is filled until t=now

		if (_addr != address(0)) {
			// If last point was in this block, the slope change has been applied already
			// But in such case we have 0 slope(s)
			_last_point.slope += (_u_new.slope - _u_old.slope);
			_last_point.bias += (_u_new.bias - _u_old.bias);
			if (_last_point.slope < 0) {
				_last_point.slope = 0;
			}
			if (_last_point.bias < 0) {
				_last_point.bias = 0;
			}
		}

		// Record the changed point into history
		point_history[_epoch] = _last_point;

		if (_addr != address(0)) {
			// Schedule the slope changes (slope is going down)
			// We subtract new_user_slope from [new_locked.end]
			// and add old_user_slope to [old_locked.end]
			if (_old_locked.end > block.timestamp) {
				// old_dslope was <something> - u_old.slope, so we cancel that
				_old_dslope += _u_old.slope;
				if (_new_locked.end == _old_locked.end) {
					_old_dslope -= _u_new.slope; // It was a new deposit, not extension
				}
				slope_changes[_old_locked.end] = _old_dslope;
			}

			if (_new_locked.end > block.timestamp) {
				if (_new_locked.end > _old_locked.end) {
					_new_dslope -= _u_new.slope; // old slope disappeared at this point
					slope_changes[_new_locked.end] = _new_dslope;
				}
				// else: we recorded it already in old_dslope
			}

			// Now handle user history
			uint256 _user_epoch = user_point_epoch[_addr] + 1;

			user_point_epoch[_addr] = _user_epoch;
			_u_new.ts = block.timestamp;
			_u_new.blk = block.number;
			user_point_history[_addr][_user_epoch] = _u_new;
		}
	}

	/*
	@notice Deposit and lock tokens for a user
	@param _addr User's wallet address
	@param _value Amount to deposit
	@param unlock_time New time when to unlock the tokens, or 0 if unchanged
	@param locked_balance Previous locked amount / timestamp
	*/
	function _deposit_for(address _addr, uint256 _value, uint256 _unlock_time, LockedBalance memory _locked_balance, int128 _type) internal
	{
		LockedBalance memory _locked = _locked_balance;
		uint256 _supply_before = supply;

		supply = _supply_before + _value;
		LockedBalance memory _old_locked = _locked;
		// Adding to existing lock, or if a lock is expired - creating a new one
		_locked.amount += int128(_value);
		if (_unlock_time != 0) _locked.end = _unlock_time;
		locked[_addr] = _locked;

		// Possibilities:
		// Both old_locked.end could be current or expired (>/< block.timestamp)
		// value == 0 (extend lock) or value > 0 (add to lock or extend lock)
		// _locked.end > block.timestamp (always)
		_checkpoint(_addr, _old_locked, _locked);

		if (_value != 0) {
			require(ERC20(token).transferFrom(_addr, address(this), _value));
		}

		emit Deposit(_addr, _value, _locked.end, _type, block.timestamp);
		emit Supply(_supply_before, _supply_before + _value);
	}

	/*
	@notice Record global data to checkpoint
	*/
	function checkpoint() external
	{
		LockedBalance memory _empty1;
		LockedBalance memory _empty2;
		_checkpoint(address(0), _empty1, _empty2);
	}

	/*
	@notice Deposit `_value` tokens for `_addr` and add to the lock
	@dev Anyone (even a smart contract) can deposit for someone else, but
	 cannot extend their locktime and deposit for a brand new user
	@param _addr User's wallet address
	@param _value Amount to add to user's lock
	*/
	function deposit_for(address _addr, uint256 _value) external nonReentrant
	{
		LockedBalance memory _locked = locked[_addr];

		require(_value > 0); // dev: need non-zero value
		require(_locked.amount > 0, "No existing lock found");
		require(_locked.end > block.timestamp, "Cannot add to expired lock. Withdraw");

		_deposit_for(_addr, _value, 0, locked[_addr], DEPOSIT_FOR_TYPE);
	}

	/*
	@notice Deposit `_value` tokens for `msg.sender` and lock until `_unlock_time`
	@param _value Amount to deposit
	@param _unlock_time Epoch time when tokens unlock, rounded down to whole weeks
	*/
	function create_lock(uint256 _value, uint256 __unlock_time) external nonReentrant
	{
		assert_not_contract(msg.sender);
		uint256 _unlock_time = (__unlock_time / WEEK) * WEEK; // Locktime is rounded down to weeks
		LockedBalance memory _locked = locked[msg.sender];

		require(_value > 0); // dev: need non-zero value
		require(_locked.amount == 0, "Withdraw old tokens first");
		require(_unlock_time > block.timestamp, "Can only lock until time in the future");
		require(_unlock_time <= block.timestamp + MAXTIME, "Voting lock can be 4 years max");

		_deposit_for(msg.sender, _value, _unlock_time, _locked, CREATE_LOCK_TYPE);
	}

	/*
	@notice Deposit `_value` additional tokens for `msg.sender` without modifying the unlock time
	@param _value Amount of tokens to deposit and add to the lock
	*/
	function increase_amount(uint256 _value) external nonReentrant
	{
		assert_not_contract(msg.sender);
		LockedBalance memory _locked = locked[msg.sender];

		require(_value > 0); // dev: need non-zero value
		require(_locked.amount > 0, "No existing lock found");
		require(_locked.end > block.timestamp, "Cannot add to expired lock. Withdraw");

		_deposit_for(msg.sender, _value, 0, _locked, INCREASE_LOCK_AMOUNT);
	}

	/*
	@notice Extend the unlock time for `msg.sender` to `_unlock_time`
	@param _unlock_time New epoch time for unlocking
	*/
	function increase_unlock_time(uint256 __unlock_time) external nonReentrant
	{
		assert_not_contract(msg.sender);
		LockedBalance memory _locked = locked[msg.sender];
		uint256 _unlock_time = (__unlock_time / WEEK) * WEEK; // Locktime is rounded down to weeks

		require(_locked.end > block.timestamp, "Lock expired");
		require(_locked.amount > 0, "Nothing is locked");
		require(_unlock_time > _locked.end, "Can only increase lock duration");
		require(_unlock_time <= block.timestamp + MAXTIME, "Voting lock can be 4 years max");

		_deposit_for(msg.sender, 0, _unlock_time, _locked, INCREASE_UNLOCK_TIME);
	}

	/*
	@notice Withdraw all tokens for `msg.sender`
	@dev Only possible if the lock has expired
	*/
	function withdraw() external nonReentrant
	{
		LockedBalance memory _locked = locked[msg.sender];
		require(block.timestamp >= _locked.end, "The lock didn't expire");
		uint256 _value = uint256(_locked.amount);

		LockedBalance memory _old_locked = _locked;
		_locked.end = 0;
		_locked.amount = 0;
		locked[msg.sender] = _locked;
		uint256 _supply_before = supply;
		supply = _supply_before - _value;

		// old_locked can have either expired <= timestamp or zero end
		// _locked has only 0 end
		// Both can have >= 0 amount
		_checkpoint(msg.sender, _old_locked, _locked);

		require(ERC20(token).transfer(msg.sender, _value));

		emit Withdraw(msg.sender, _value, block.timestamp);
		emit Supply(_supply_before, _supply_before - _value);
	}

	// The following ERC20/minime-compatible methods are not real balanceOf and supply!
	// They measure the weights for the purpose of voting, so they don't represent
	// real coins.

	/*
	@notice Binary search to estimate timestamp for block number
	@param _block Block to find
	@param max_epoch Don't go beyond this epoch
	@return Approximate timestamp for block
	*/
	function find_block_epoch(uint256 _block, uint256 _max_epoch) internal view returns (uint256)
	{
		// Binary search
		uint256 _min = 0;
		uint256 _max = _max_epoch;
		for (uint256 _i = 0; _i < 128; _i++) { // Will be always enough for 128-bit numbers
			if (_min >= _max) break;
			uint256 _mid = (_min + _max + 1) / 2;
			if (point_history[_mid].blk <= _block)
				_min = _mid;
			else
				_max = _mid - 1;
		}
		return _min;
	}

	/*
	@notice Get the current voting power for `msg.sender`
	@dev Adheres to the ERC20 `balanceOf` interface for Aragon compatibility
	@param addr User wallet address
	@param _t Epoch time to return voting power at
	@return User voting power
	*/
	function balanceOf(address _addr) external view returns (uint256)
	{
		return balanceOf(_addr, block.timestamp);
	}
	function balanceOf(address _addr, uint256 _t) public view returns (uint256)
	{
		uint256 _epoch = user_point_epoch[_addr];
		if (_epoch == 0) return 0;
		Point memory _last_point = user_point_history[_addr][_epoch];
		_last_point.bias -= _last_point.slope * int128(_t - _last_point.ts);
		if (_last_point.bias < 0) _last_point.bias = 0;
		return uint256(_last_point.bias);
	}

	/*
	@notice Measure voting power of `addr` at block height `_block`
	@dev Adheres to MiniMe `balanceOfAt` interface: https://github.com/Giveth/minime
	@param addr User's wallet address
	@param _block Block to calculate the voting power at
	@return Voting power
	*/
	function balanceOfAt(address _addr, uint256 _block) external view returns (uint256)
	{
		// Copying and pasting totalSupply code because Vyper cannot pass by
		// reference yet
		require(_block <= block.number);

		// Binary search
		uint256 _min = 0;
		uint256 _max = user_point_epoch[_addr];
		for (uint256 _i =0; _i < 128; _i++) { // Will be always enough for 128-bit numbers
			if (_min >= _max) break;
			uint256 _mid = (_min + _max + 1) / 2;
			if (user_point_history[_addr][_mid].blk <= _block)
				_min = _mid;
			else
				_max = _mid - 1;
		}

		Point memory _upoint = user_point_history[_addr][_min];

		uint256 _max_epoch = epoch;
		uint256 _epoch = find_block_epoch(_block, _max_epoch);
		Point memory _point_0 = point_history[_epoch];
		uint256 _d_block = 0;
		uint256 _d_t = 0;
		if (_epoch < _max_epoch) {
			Point memory _point_1 = point_history[_epoch + 1];
			_d_block = _point_1.blk - _point_0.blk;
			_d_t = _point_1.ts - _point_0.ts;
		} else {
			_d_block = block.number - _point_0.blk;
			_d_t = block.timestamp - _point_0.ts;
		}
		uint256 _block_time = _point_0.ts;
		if (_d_block != 0) {
			_block_time += _d_t * (_block - _point_0.blk) / _d_block;
		}

		_upoint.bias -= _upoint.slope * int128(_block_time - _upoint.ts);
		if (_upoint.bias >= 0)
			return uint256(_upoint.bias);
		else
			return 0;
	}

	/*
	@notice Calculate total voting power at some point in the past
	@param point The point (bias/slope) to start search from
	@param t Time to calculate the total voting power at
	@return Total voting power at that time
	*/
	function supply_at(Point memory _point, uint256 _t) internal view returns (uint256)
	{
		Point memory _last_point = _point;
		uint256 _t_i = (_last_point.ts / WEEK) * WEEK;
		for (uint256 _i = 0; _i < 255; _i++) {
			_t_i += WEEK;
			int128 _d_slope = 0;
			if (_t_i > _t)
				_t_i = _t;
			else
				_d_slope = slope_changes[_t_i];
			_last_point.bias -= _last_point.slope * int128(_t_i - _last_point.ts);
			if (_t_i == _t) break;
			_last_point.slope += _d_slope;
			_last_point.ts = _t_i;
		}
		if (_last_point.bias < 0) _last_point.bias = 0;
		return uint256(_last_point.bias);
	}

	/*
	@notice Calculate total voting power
	@dev Adheres to the ERC20 `totalSupply` interface for Aragon compatibility
	@return Total voting power
	*/
	function totalSupply() external view returns (uint256)
	{
		return totalSupply(block.timestamp);
	}
	function totalSupply(uint256 _t) public view returns (uint256)
	{
		uint256 _epoch = epoch;
		Point memory last_point = point_history[_epoch];
		return supply_at(last_point, _t);
	}

	/*
	@notice Calculate total voting power at some point in the past
	@param _block Block to calculate the total voting power at
	@return Total voting power at `_block`
	*/
	function totalSupplyAt(uint256 _block) external view returns (uint256)
	{
		require(_block <= block.number);
		uint256 _epoch = epoch;
		uint256 _target_epoch = find_block_epoch(_block, _epoch);

		Point memory _point = point_history[_target_epoch];
		uint256 _dt = 0;
		if (_target_epoch < _epoch) {
			Point memory _point_next = point_history[_target_epoch + 1];
			if (_point.blk != _point_next.blk) {
				_dt = (_block - _point.blk) * (_point_next.ts - _point.ts) / (_point_next.blk - _point.blk);
			}
		} else {
			if (_point.blk != block.number) {
				_dt = (_block - _point.blk) * (block.timestamp - _point.ts) / (block.number - _point.blk);
			}
		}
		// Now dt contains info on how far are we beyond point

		return supply_at(_point, _point.ts + _dt);
	}

	// Dummy methods for compatibility with Aragon

	/*
	@dev Dummy method required for Aragon compatibility
	*/
	function changeController(address _newController) external
	{
		require(msg.sender == controller);
		controller = _newController;
	}
}
