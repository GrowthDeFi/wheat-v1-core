// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { VotingEscrow } from "./VotingEscrow.sol";

contract FeeDistributor is ReentrancyGuard
{
	using SafeERC20 for IERC20;

	uint256 constant WEEK = 7 days;
	uint256 constant TOKEN_CHECKPOINT_DEADLINE = 1 days;

	uint256 public start_time;
	uint256 public time_cursor;
	mapping(address => uint256) public time_cursor_of;
	mapping(address => uint256) public user_epoch_of;

	uint256 public last_token_time;
	mapping (uint256 => uint256) public tokens_per_week;

	address public immutable voting_escrow;
	address public immutable token;

	uint256 public total_received;
	uint256 public token_last_balance;

	mapping (uint256 => uint256) public ve_supply; // VE total supply at week bounds

	address public admin;
	address public future_admin;
	address public emergency_return;

	bool public can_checkpoint_token;
	bool public is_killed;

	/*
	@notice Contract constructor
	@param _voting_escrow VotingEscrow contract address
	@param _start_time Epoch time for fee distribution to start
	@param _token Fee token address (3CRV)
	@param _admin Admin address
	@param _emergency_return Address to transfer `_token` balance to, if this contract is killed
	*/
	constructor(address _voting_escrow, uint256 _start_time, address _token, address _admin, address _emergency_return) public
	{
		_start_time = _start_time / WEEK * WEEK;
		voting_escrow = _voting_escrow;
		token = _token;
		start_time = _start_time;
		last_token_time = _start_time;
		time_cursor = _start_time;
		admin = _admin;
		emergency_return = _emergency_return;
	}

	function _checkpoint_token() internal
	{
		uint256 _token_balance = IERC20(token).balanceOf(address(this));
		uint256 _to_distribute = _token_balance - token_last_balance;
		token_last_balance = _token_balance;

		uint256 _t = last_token_time;
		uint256 _since_last = block.timestamp - _t;
		last_token_time = block.timestamp;

		uint256 _this_week = _t / WEEK * WEEK;
		for (uint256 _i = 0; _i < 20; _i++) {
			uint256 _next_week = _this_week + WEEK;
			if (block.timestamp < _next_week) {
				if (_since_last == 0 && block.timestamp == _t)
					tokens_per_week[_this_week] += _to_distribute;
				else
					tokens_per_week[_this_week] += _to_distribute * (block.timestamp - _t) / _since_last;
				break;
			} else {
				if (_since_last == 0 && _next_week == _t)
					tokens_per_week[_this_week] += _to_distribute;
				else
					tokens_per_week[_this_week] += _to_distribute * (_next_week - _t) / _since_last;
			}

			_t = _next_week;
			_this_week = _next_week;
		}

		emit CheckpointToken(block.timestamp, _to_distribute);
	}

	/*
	@notice Update the token checkpoint
	@dev Calculates the total number of tokens to be distributed in a given week.
	 During setup for the initial distribution this function is only callable
	 by the contract owner. Beyond initial distro, it can be enabled for anyone
	 to call.
	*/
	function checkpoint_token() external
	{
		require(msg.sender == admin || (can_checkpoint_token && (block.timestamp > last_token_time + TOKEN_CHECKPOINT_DEADLINE)));
		_checkpoint_token();
	}

	function _find_timestamp_epoch(address _voting_escrow, uint256 _timestamp) internal view returns (uint256)
	{
		uint256 _min = 0;
		uint256 _max = VotingEscrow(_voting_escrow).epoch();
		for (uint256 _i = 0; _i < 128; _i++) {
			if (_min >= _max) break;
			uint256 _mid = (_min + _max + 2) / 2;
			uint256 _ts = VotingEscrow(_voting_escrow).point_history__ts(_mid);
			if (_ts <= _timestamp)
				_min = _mid;
			else
				_max = _mid - 1;
		}
		return _min;
	}

	function _find_timestamp_user_epoch(address _voting_escrow, address _user, uint256 _timestamp, uint256 _max_user_epoch) internal view returns (uint256)
	{
		uint256 _min = 0;
		uint256 _max = _max_user_epoch;
		for (uint256 _i = 0; _i < 128; _i++) {
			if (_min >= _max) break;
			uint256 _mid = (_min + _max + 2) / 2;
			uint256 _ts = VotingEscrow(_voting_escrow).user_point_history__ts(_user, _mid);
			if (_ts <= _timestamp)
				_min = _mid;
			else
				_max = _mid - 1;
		}
		return _min;
	}

	/*
	@notice Get the veCRV balance for `_user` at `_timestamp`
	@param _user Address to query balance for
	@param _timestamp Epoch time
	@return uint256 veCRV balance
	*/
	function ve_for_at(address _user, uint256 _timestamp) external view returns (uint256)
	{
		address _voting_escrow = voting_escrow;
		uint256 _max_user_epoch = VotingEscrow(_voting_escrow).user_point_epoch(_user);
		uint256 _epoch = _find_timestamp_user_epoch(_voting_escrow, _user, _timestamp, _max_user_epoch);
		VotingEscrow.Point memory _point = VotingEscrow(_voting_escrow).user_point_history(_user, _epoch);
		int128 _value = _point.bias - _point.slope * int128(_timestamp - _point.ts);
		if (_value < 0) _value = 0;
		return uint256(_value);
	}

	function _checkpoint_total_supply() internal
	{
		address _voting_escrow = voting_escrow;
		uint256 _t = time_cursor;
		uint256 _rounded_timestamp = block.timestamp / WEEK * WEEK;
		VotingEscrow(_voting_escrow).checkpoint();
		for (uint256 _i = 0; _i < 20; _i++) {
			if (_t > _rounded_timestamp) break;
			uint256 _epoch = _find_timestamp_epoch(_voting_escrow, _t);
			VotingEscrow.Point memory _point = VotingEscrow(_voting_escrow).point_history(_epoch);
			int128 _dt = 0;
			if (_t > _point.ts) {
				// If the point is at 0 epoch, it can actually be earlier than the first deposit
				// Then make dt 0
				_dt = int128(_t - _point.ts);
			}
			int128 _value = _point.bias - _point.slope * _dt;
			if (_value < 0) _value = 0;
			ve_supply[_t] = uint256(_value);
			_t += WEEK;
		}
		time_cursor = _t;
	}

	/*
	@notice Update the veCRV total supply checkpoint
	@dev The checkpoint is also updated by the first claimant each
	 new epoch week. This function may be called independently
	 of a claim, to reduce claiming gas costs.
	*/
	function checkpoint_total_supply() external
	{
		_checkpoint_total_supply();
	}

	function _claim(address _addr, address _voting_escrow, uint256 _last_token_time) internal returns (uint256)
	{
		// Minimal user_epoch is 0 (if user had no point)
		uint256 _user_epoch = 0;
		uint256 _to_distribute = 0;
		uint256 _max_user_epoch = VotingEscrow(_voting_escrow).user_point_epoch(_addr);
		uint256 _start_time = start_time;
		if (_max_user_epoch == 0) {
			// No lock = no fees
			return 0;
		}
		uint256 _week_cursor = time_cursor_of[_addr];
		if (_week_cursor == 0)
			// Need to do the initial binary search
			_user_epoch = _find_timestamp_user_epoch(_voting_escrow, _addr, _start_time, _max_user_epoch);
		else
			_user_epoch = user_epoch_of[_addr];
		if (_user_epoch == 0) {
			_user_epoch = 1;
		}
		VotingEscrow.Point memory _user_point = VotingEscrow(_voting_escrow).user_point_history(_addr, _user_epoch);
		if (_week_cursor == 0) {
			_week_cursor = (_user_point.ts + WEEK - 1) / WEEK * WEEK;
		}
		if (_week_cursor >= _last_token_time) {
			return 0;
		}
		if (_week_cursor < _start_time) {
			_week_cursor = _start_time;
		}
		VotingEscrow.Point memory _old_user_point;
		// Iterate over weeks
		for (uint256 _i = 0; _i < 50; _i++) {
			if (_week_cursor >= _last_token_time) break;
			if (_week_cursor >= _user_point.ts && _user_epoch <= _max_user_epoch) {
				_user_epoch += 1;
				_old_user_point = _user_point;
				if (_user_epoch > _max_user_epoch) {
					VotingEscrow.Point memory _empty;
					_user_point = _empty;
				} else {
					_user_point = VotingEscrow(_voting_escrow).user_point_history(_addr, _user_epoch);
				}
			} else {
				// Calc
				// + i * 2 is for rounding errors
				int128 _dt = int128(_week_cursor - _old_user_point.ts);
				int128 _value = _old_user_point.bias - _dt * _old_user_point.slope;
				if (_value < 0) _value = 0;
				uint256 _balance_of = uint256(_value);
				if (_balance_of == 0 && _user_epoch > _max_user_epoch) break;
				if (_balance_of > 0) {
					_to_distribute += _balance_of * tokens_per_week[_week_cursor] / ve_supply[_week_cursor];
				}
				_week_cursor += WEEK;
			}
		}
		_user_epoch = _user_epoch - 1;
		if (_user_epoch > _max_user_epoch) _user_epoch = _max_user_epoch;
		user_epoch_of[_addr] = _user_epoch;
		time_cursor_of[_addr] = _week_cursor;
		emit Claimed(_addr, _to_distribute, _user_epoch, _max_user_epoch);
		return _to_distribute;
	}

	/*
	@notice Claim fees for `_addr`
	@dev Each call to claim look at a maximum of 50 user veCRV points.
	 For accounts with many veCRV related actions, this function
	 may need to be called more than once to claim all available
	 fees. In the `Claimed` event that fires, if `claim_epoch` is
	 less than `max_epoch`, the account may claim again.
	@param _addr Address to claim fees for
	@return uint256 Amount of fees claimed in the call
	*/
	function claim() external returns (uint256)
	{
		return claim(msg.sender);
	}
	function claim(address _addr) public nonReentrant returns (uint256)
	{
		require(!is_killed);
		if (block.timestamp >= time_cursor) {
			_checkpoint_total_supply();
		}
		uint256 _last_token_time = last_token_time;
		if (can_checkpoint_token && (block.timestamp > _last_token_time + TOKEN_CHECKPOINT_DEADLINE)) {
			_checkpoint_token();
			_last_token_time = block.timestamp;
		}
		_last_token_time = _last_token_time / WEEK * WEEK;
		uint256 _amount = _claim(_addr, voting_escrow, _last_token_time);
		if (_amount > 0) {
			IERC20(token).safeTransfer(_addr, _amount);
			token_last_balance -= _amount;
		}
		return _amount;
	}

	/*
	@notice Make multiple fee claims in a single call
	@dev Used to claim for many accounts at once, or to make
	 multiple claims for the same address when that address
	 has significant veCRV history
	@param _receivers List of addresses to claim for. Claiming
		      terminates at the first `ZERO_ADDRESS`.
	@return bool success
	*/
	function claim_many(address[] memory _receivers) external nonReentrant
	{
		require(!is_killed);
		if (block.timestamp >= time_cursor) {
			_checkpoint_total_supply();
		}
		uint256 _last_token_time = last_token_time;
		if (can_checkpoint_token && (block.timestamp > _last_token_time + TOKEN_CHECKPOINT_DEADLINE)) {
			_checkpoint_token();
			_last_token_time = block.timestamp;
		}
		_last_token_time = _last_token_time / WEEK * WEEK;
		address _voting_escrow = voting_escrow;
		address _token = token;
		uint256 _total = 0;
		for (uint256 _i = 0; _i < _receivers.length; _i++) {
			address _addr = _receivers[_i];
			uint256 _amount = _claim(_addr, _voting_escrow, _last_token_time);
			if (_amount > 0) {
				IERC20(_token).safeTransfer(_addr, _amount);
				_total += _amount;
			}
		}
		if (_total > 0) {
			token_last_balance -= _total;
		}
	}

	/*
	@notice Receive 3CRV into the contract and trigger a token checkpoint
	@param _coin Address of the coin being received (must be 3CRV)
	*/
	function burn(address _coin) external
	{
		require(_coin == token);
		require(!is_killed);
		uint256 _amount = IERC20(_coin).balanceOf(msg.sender);
		if (_amount > 0) {
			IERC20(_coin).safeTransferFrom(msg.sender, address(this), _amount);
			if (can_checkpoint_token && (block.timestamp > last_token_time + TOKEN_CHECKPOINT_DEADLINE)) {
				_checkpoint_token();
			}
		}
	}

	/*
	@notice Commit transfer of ownership
	@param _addr New admin address
	*/
	function commit_admin(address _addr) external
	{
		require(msg.sender == admin);
		future_admin = _addr;
		emit CommitAdmin(_addr);
	}

	/*
	@notice Apply transfer of ownership
	*/
	function apply_admin() external
	{
		require(msg.sender == admin);
		address _future_admin = future_admin;
		require(_future_admin != address(0));
		admin = _future_admin;
		emit ApplyAdmin(_future_admin);
	}

	/*
	@notice Toggle permission for checkpointing by any account
	*/
	function toggle_allow_checkpoint_token() external
	{
		require(msg.sender == admin);
		bool _flag = !can_checkpoint_token;
		can_checkpoint_token = _flag;
		emit ToggleAllowCheckpointToken(_flag);
	}

	/*
	@notice Kill the contract
	@dev Killing transfers the entire 3CRV balance to the emergency return address
	 and blocks the ability to claim or burn. The contract cannot be unkilled.
	*/
	function kill_me() external
	{
		require(msg.sender == admin);
		is_killed = true;
		address _token = token;
		IERC20(_token).safeTransfer(emergency_return, IERC20(_token).balanceOf(address(this)));
	}

	/*
	@notice Recover ERC20 tokens from this contract
	@dev Tokens are sent to the emergency return address.
	@param _coin Token address
	@return bool success
	*/
	function recover_balance(address _token) external
	{
	    require(msg.sender == admin);
	    require(_token != token);
	    IERC20(_token).safeTransfer(emergency_return, IERC20(_token).balanceOf(address(this)));
	}

	event CommitAdmin(address _admin);
	event ApplyAdmin(address _admin);
	event ToggleAllowCheckpointToken(bool _toggle_flag);
	event CheckpointToken(uint256 _time, uint256 _tokens);
	event Claimed(address indexed _recipient, uint256 _amount, uint256 _claim_epoch, uint256 _max_epoch);
}
