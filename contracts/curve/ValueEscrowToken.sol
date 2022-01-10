// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { Transfers } from "../modules/Transfers.sol";

import { IERC20Historical } from "./IERC20Historical.sol";

contract ValueEscrowToken is IERC20Historical, ReentrancyGuard
{
	struct UserInfo {
		uint256 amount;
		uint256 unlock;
	}

	struct Point {
		uint256 bias;
		uint256 slope;
		uint256 time;
	}

	uint256 public constant UNLOCK_BASIS = 1 weeks;
	uint256 public constant MAX_LOCK_TIME = 4 * 365 days; // 4 years

	string public name;
	string public symbol;
	uint8 public immutable decimals;

	address public immutable reserveToken;

	mapping(address => UserInfo) public userInfo;

	Point[] private points_;
	mapping(address => Point[]) private userPoints_;
	mapping(uint256 => uint256) private slopeDecay_;

	constructor(string memory _name, string memory _symbol, uint8 _decimals, address _reserveToken)
		public
	{
		name = _name;
		symbol = _symbol;
		decimals = _decimals;
		reserveToken = _reserveToken;
		_appendPoint(points_, 0, 0, block.timestamp);
	}

	function deposit(uint256 _amount, uint256 _newUnlock) external nonReentrant
	{
		require(_newUnlock % UNLOCK_BASIS == 0 && block.timestamp < _newUnlock && _newUnlock <= block.timestamp + MAX_LOCK_TIME, "invalid unlock");
		UserInfo storage _user = userInfo[msg.sender];
		uint256 _oldUnlock = _user.unlock;
		require(_oldUnlock == 0 || _oldUnlock > block.timestamp, "expired unlock");
		require(_newUnlock >= _oldUnlock, "shortened unlock");
		uint256 _oldAmount = _user.amount;
		uint256 _newAmount = _oldAmount + _amount;
		_user.amount = _newAmount;
		_user.unlock = _newUnlock;
		_checkpoint(msg.sender, _oldAmount, _oldUnlock, _newAmount, _newUnlock);
		Transfers._pullFunds(reserveToken, msg.sender, _amount);
		emit Deposit(msg.sender, _amount, _newUnlock);
	}

	function withdraw() external nonReentrant
	{
		UserInfo storage _user = userInfo[msg.sender];
		uint256 _unlock = _user.unlock;
		require(block.timestamp >= _unlock, "not available");
		uint256 _amount = _user.amount;
		_user.amount = 0;
		_user.unlock = 0;
		_checkpoint(msg.sender, _amount, _unlock, 0, 0);
		Transfers._pushFunds(reserveToken, msg.sender, _amount);
		emit Withdraw(msg.sender, _amount);
	}

	function checkpoint() external override
	{
		Point[] storage _points = points_;
		Point storage _point = _points[_points.length - 1];
		if (block.timestamp >= _point.time + UNLOCK_BASIS) {
			_checkpoint(address(0), 0, 0, 0, 0);
		}
	}

	function totalSupply(uint256 _when) public override view returns (uint256 _totalSupply)
	{
		Point[] storage _points = points_;
		uint256 _index = _findPoint(_points, _when);
		if (_index == 0) return 0;
		Point storage _point = _points[_index - 1];
		uint256 _bias = _point.bias;
		uint256 _slope = _point.slope;
		uint256 _start = _point.time;
		uint256 _week = (_start / UNLOCK_BASIS) * UNLOCK_BASIS;
		while (true) {
			uint256 _nextWeek = _week + UNLOCK_BASIS;
			uint256 _end = _nextWeek < _when ? _nextWeek : _when;
			uint256 _ellapsed = _end - _start;
			uint256 _maxEllapsed = _slope > 0 ? _bias / _slope : uint256(-1);
			_bias = _ellapsed <= _maxEllapsed ? _bias - _slope * _ellapsed : 0;
			if (_end == _nextWeek) _slope -= slopeDecay_[_nextWeek];
			if (_end == _when) break;
			_start = _end;
			_week = _nextWeek;
		}
		return _bias;
	}

	function balanceOf(address _account, uint256 _when) public override view returns (uint256 _balance)
	{
		Point[] storage _points = userPoints_[_account];
		uint256 _index = _findPoint(_points, _when);
		if (_index == 0) return 0;
		Point storage _point = _points[_index - 1];
		uint256 _bias = _point.bias;
		uint256 _slope = _point.slope;
		uint256 _start = _point.time;
		uint256 _end = _when;
		uint256 _ellapsed = _end - _start;
		uint256 _maxEllapsed = _slope > 0 ? _bias / _slope : uint256(-1);
		return _ellapsed <= _maxEllapsed ? _bias - _slope * _ellapsed : 0;
	}

	function totalSupply() external view override returns (uint256 _totalSupply)
	{
		return totalSupply(block.timestamp);
	}

	function balanceOf(address _account) external view override returns (uint256 _balance)
	{
		return balanceOf(_account, block.timestamp);
	}

	function allowance(address _account, address _spender) external view override returns (uint256 _allowance)
	{
		_account; _spender;
		return 0;
	}

	function approve(address _spender, uint256 _amount) external override returns (bool _success)
	{
		require(false, "forbidden");
		_spender; _amount;
		return false;
	}

	function transfer(address _to, uint256 _amount) external override returns (bool _success)
	{
		require(false, "forbidden");
		_to; _amount;
		return false;
	}

	function transferFrom(address _from, address _to, uint256 _amount) external override returns (bool _success)
	{
		require(false, "forbidden");
		_from; _to; _amount;
		return false;
	}

	function _findPoint(Point[] storage _points, uint256 _when) internal view returns (uint256 _index)
	{
		uint256 _min = 0;
		uint256 _max = _points.length;
		if (_when >= block.timestamp) return _max;
		while (_min < _max) {
			uint256 _mid = (_min + _max) / 2;
			if (_points[_mid].time <= _when)
				_min = _mid + 1;
			else
				_max = _mid;
		}
		return _min;
	}

	function _appendPoint(Point[] storage _points, uint256 _bias, uint256 _slope, uint256 _time) internal
	{
		uint256 _length = _points.length;
		if (_length > 0) {
			Point storage _point = _points[_length - 1];
			if (_point.time == _time) {
				_point.bias = _bias;
				_point.slope = _slope;
				return;
			}
			require(_time > _point.time, "invalid time");
		}
		_points.push(Point({ bias: _bias, slope: _slope, time: _time }));
	}

	function _checkpoint(address _account, uint256 _oldAmount, uint256 _oldUnlock, uint256 _newAmount, uint256 _newUnlock) internal
	{
		uint256 _oldBias = 0;
		uint256 _oldSlope = 0;
		if (_oldUnlock > block.timestamp && _oldAmount > 0) {
			_oldSlope = _oldAmount / MAX_LOCK_TIME;
			_oldBias = _oldSlope * (_oldUnlock - block.timestamp);
			slopeDecay_[_oldUnlock] -= _oldSlope;
		}

		uint256 _newBias = 0;
		uint256 _newSlope = 0;
		if (_newUnlock > block.timestamp && _newAmount > 0) {
			_newSlope = _newAmount / MAX_LOCK_TIME;
			_newBias = _newSlope * (_newUnlock - block.timestamp);
			slopeDecay_[_newUnlock] += _newSlope;
		}

		{
			Point[] storage _points = points_;
			uint256 _when = block.timestamp;
			Point storage _point = _points[_points.length - 1];
			uint256 _bias = _point.bias;
			uint256 _slope = _point.slope;
			uint256 _start = _point.time;
			uint256 _week = (_start / UNLOCK_BASIS) * UNLOCK_BASIS;
			while (true) {
				uint256 _nextWeek = _week + UNLOCK_BASIS;
				uint256 _end = _nextWeek < _when ? _nextWeek : _when;
				uint256 _ellapsed = _end - _start;
				uint256 _maxEllapsed = _slope > 0 ? _bias / _slope : uint256(-1);
				_bias = _ellapsed <= _maxEllapsed ? _bias - _slope * _ellapsed : 0;
				if (_end == _nextWeek) _slope -= slopeDecay_[_nextWeek];
				if (_end == _when) break;
				_appendPoint(_points, _bias, _slope, _end);
				_start = _end;
				_week = _nextWeek;
			}
			_bias += _newBias - _oldBias;
			_slope += _newSlope - _oldSlope;
			_appendPoint(_points, _bias, _slope, block.timestamp);
		}

		if (_account != address(0)) {
			_appendPoint(userPoints_[_account], _newBias, _newSlope, block.timestamp);
		}
	}

	event Deposit(address indexed _account, uint256 _amount, uint256 indexed _unlock);
	event Withdraw(address indexed _account, uint256 _amount);
}
