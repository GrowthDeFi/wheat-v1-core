// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { Transfers } from "../modules/Transfers.sol";

contract VotingEscrowToken is IERC20, ReentrancyGuard
{
	using SafeMath for uint256;

	struct Point {
		int128 bias;
		int128 slope;
		uint256 time;
	}

	struct UserInfo {
		uint256 amount;
		uint256 unlock;
	}

	uint256 constant MAX_LOCK_TIME = 4 * 365 days; // 4 years

	string public name;
	string public symbol;
	uint8 public immutable decimals;

	address public immutable reserveToken;

	mapping(address => UserInfo) public userInfo;

	Point[] public points;
	mapping(address => Point[]) public userPoints;
	mapping(uint256 => int128) public slopeChanges;

	constructor(string memory _name, string memory _symbol, uint8 _decimals, address _reserveToken)
		public
	{
		name = _name;
		symbol = _symbol;
		decimals = _decimals;
		reserveToken = _reserveToken;
		points.push(Point({
			bias: 0,
			slope: 0,
			time: block.timestamp
		}));
	}

	function deposit(uint256 _amount, uint256 _unlock) external nonReentrant
	{
		_unlock = (_unlock / 1 weeks) * 1 weeks;
		require(block.timestamp < _unlock && _unlock <= block.timestamp + MAX_LOCK_TIME, "invalid unlock");
		UserInfo storage _user = userInfo[msg.sender];
		require(_user.unlock == 0 || _user.unlock > block.timestamp, "expired");
		require(_unlock >= _user.unlock, "invalid extension");
		uint256 _oldAmount = _user.amount;
		uint256 _oldUnlock = _user.unlock;
		_user.amount += _amount;
		_user.unlock = _unlock;
		_checkpoint(msg.sender, _oldAmount, _oldUnlock, _user.amount, _user.unlock);
		Transfers._pullFunds(reserveToken, msg.sender, _amount);
		emit Deposit(msg.sender, _amount, _unlock);
	}

	function withdraw() external nonReentrant
	{
		UserInfo storage _user = userInfo[msg.sender];
		require(block.timestamp >= _user.unlock, "not available");
		uint256 _amount = _user.amount;
		uint256 _unlock = _user.unlock;
		_user.amount = 0;
		_user.unlock = 0;
		_checkpoint(msg.sender, _amount, _unlock, 0, 0);
		Transfers._pushFunds(reserveToken, msg.sender, _amount);
		emit Withdraw(msg.sender, _amount);
	}

	function checkpoint() external
	{
		_checkpoint(address(0), 0, 0, 0, 0);
	}

	function totalSupply() external view override returns (uint256 _totalSupply)
	{
		return totalSupply(block.timestamp);
	}

	function totalSupply(uint256 _when) public view returns (uint256 _totalSupply)
	{
		Point storage _point = points[points.length - 1];
		int128 _bias = _point.bias;
		int128 _slope = _point.slope;
		uint256 _time = _point.time;
		uint256 _ti = (_time / 1 weeks) * 1 weeks;
		for (uint256 _i = 0; _i < 255; _i++) {
			_ti += 1 weeks;
			int128 _slopeChange;
			if (_ti <= _when)
				_slopeChange = slopeChanges[_ti];
			else {
				_slopeChange = 0;
				_ti = _when;
			}
			_bias -= _slope * int128(_ti - _time);
			if (_ti == _when) break;
			_slope += _slopeChange;
			_time = _ti;
		}
		if (_bias < 0) _bias = 0;
		return uint256(_bias);
	}

	function balanceOf(address _account) external view override returns (uint256 _balance)
	{
		return balanceOf(_account, block.timestamp);
	}

	function balanceOf(address _account, uint256 _when) public view returns (uint256 _balance)
	{
		Point[] storage _points = userPoints[_account];
		uint256 _length = _points.length;
		if (_length == 0) return 0;
		Point storage _point = _points[_length - 1];
		int128 _bias = _point.bias - _point.slope * int128(_when - _point.time);
		if (_bias < 0) _bias = 0;
		return uint256(_bias);
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

	function _checkpoint(address _account, uint256 _oldAmount, uint256 _oldUnlock, uint256 _newAmount, uint256 _newUnlock) internal
	{
		int128 _oldSlopeChange = 0;
		int128 _newSlopeChange = 0;
		int128 _oldSlope = 0;
		int128 _oldBias = 0;
		int128 _newSlope = 0;
		int128 _newBias = 0;

		if (_account != address(0)) {
			if (_oldUnlock > block.timestamp && _oldAmount > 0) {
				_oldSlope = int128(_oldAmount) / int128(MAX_LOCK_TIME);
				_oldBias = _oldSlope * int128(_oldUnlock - block.timestamp);
			}
			if (_newUnlock > block.timestamp && _newAmount > 0) {
				_newSlope = int128(_newAmount) / int128(MAX_LOCK_TIME);
				_newBias = _newSlope * int128(_newUnlock - block.timestamp);
			}
			_oldSlopeChange = slopeChanges[_oldUnlock];
			if (_newUnlock > 0) {
				_newSlopeChange = _newUnlock == _oldUnlock ? _oldSlopeChange : slopeChanges[_newUnlock];
			}
		}

		int128 _bias;
		int128 _slope;
		uint256 _time;
		{
			Point storage _point = points[points.length - 1];
			_bias = _point.bias;
			_slope = _point.slope;
			_time = _point.time;
		}

		{
			uint256 _ti = (_time / 1 weeks) * 1 weeks;
			for (uint256 _i = 0; _i < 255; _i++) {
				_ti += 1 weeks;
				int128 _slopeChange;
				if (_ti <= block.timestamp)
					_slopeChange = slopeChanges[_ti];
				else {
					_slopeChange = 0;
					_ti = block.timestamp;
				}
				_bias -= _slope * int128(_ti - _time);
				_slope += _slopeChange;
				if (_bias < 0) _bias = 0;
				if (_slope < 0) _slope = 0;
				_time = _ti;
				if (_ti == block.timestamp) break;
				points.push(Point({
					bias: _bias,
					slope: _slope,
					time: _time
				}));
			}
		}

		if (_account != address(0)) {
			_slope += _newSlope - _oldSlope;
			_bias += _newBias - _oldBias;
			if (_slope < 0) _slope = 0;
			if (_bias < 0) _bias = 0;
		}

		points.push(Point({
			bias: _bias,
			slope: _slope,
			time: _time
		}));

		if (_account != address(0)) {
			if (_oldUnlock > block.timestamp) {
				_oldSlopeChange += _oldSlope;
				if (_newUnlock == _oldUnlock) {
					_oldSlopeChange -= _newSlope;
				}
				slopeChanges[_oldUnlock] = _oldSlopeChange;
			}
			if (_newUnlock > block.timestamp) {
				if (_newUnlock > _oldUnlock) {
					_newSlopeChange -= _newSlope;
					slopeChanges[_newUnlock] = _newSlopeChange;
				}
			}
			userPoints[_account].push(Point({
				bias: _newBias,
				slope: _newSlope,
				time: block.timestamp
			}));
		}
	}

	event Deposit(address indexed _account, uint256 _amount, uint256 indexed _unlock);
	event Withdraw(address indexed _account, uint256 _amount);
}
