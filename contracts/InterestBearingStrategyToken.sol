// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";
import { Wrapping } from "./modules/Wrapping.sol";

import { Bank } from "./interop/AlphaHomora.sol";

contract InterestBearingStrategyToken is ERC20, ReentrancyGuard, WhitelistGuard
{
	using SafeMath for uint256;

	uint256 constant DEPOSIT_FEE_BUYBACK_SHARE = 80e16; // 80%
	uint256 constant DEPOSIT_FEE_DEV_SHARE = 20e16; // 20%

	uint256 constant MAXIMUM_DEPOSIT_FEE = 1e16; // 1%
	uint256 constant DEFAULT_DEPOSIT_FEE = 1e15; // 0.1%

	address public immutable reserveToken;
	address public immutable interestToken;

	address public dev;
	address public treasury;
	address public buyback;

	uint256 public depositFee = DEFAULT_DEPOSIT_FEE;

	constructor (string memory _name, string memory _symbol, uint8 _decimals,
		address _reserveToken, address _interestToken,
		address _dev, address _treasury, address _buyback)
		ERC20(_name, _symbol) public
	{
		_setupDecimals(_decimals);
		reserveToken = _reserveToken;
		interestToken = _interestToken;
		dev = _dev;
		treasury = _treasury;
		buyback = _buyback;
		_mint(address(1), 1); // avoids division by zero
	}

	function totalReserve() public view returns (uint256 _totalReserve)
	{
		_totalReserve = _calcUnderlyingAmountFromUnderlyingShares(Transfers._getBalance(interestToken));
		if (_totalReserve == uint256(-1)) return _totalReserve;
		return _totalReserve + 1; // avoids division by zero
	}

	function calcSharesFromAmount(uint256 _amount) external view returns (uint256 _shares)
	{
		(,,,_shares) = _calcSharesFromAmount(_amount);
		return _shares;
	}

	function calcAmountFromShares(uint256 _shares) external view returns (uint256 _amount)
	{
		return _calcUnderlyingAmountFromUnderlyingShares(_calcUnderlyingSharesFromUnderlyingAmount(_calcAmountFromShares(_shares)));
	}

	function deposit(uint256 _amount) external onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		(uint256 _devAmount, uint256 _buybackAmount, uint256 _netAmount, uint256 _shares) = _calcSharesFromAmount(_amount);
		Transfers._pullFunds(reserveToken, _from, _amount);
		Transfers._pushFunds(reserveToken, dev, _devAmount);
		Transfers._pushFunds(reserveToken, buyback, _buybackAmount);
		Wrapping._unwrap(reserveToken, _netAmount);
		Bank(interestToken).deposit{value: _netAmount}();
		_mint(_from, _shares);
	}

	function withdraw(uint256 _shares) external onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		uint256 _underlyingShares = _calcUnderlyingSharesFromUnderlyingAmount(_calcAmountFromShares(_shares));
		uint256 _amount = _calcUnderlyingAmountFromUnderlyingShares(_underlyingShares);
		_burn(_from, _shares);
		Bank(interestToken).withdraw(_underlyingShares);
		Wrapping._wrap(reserveToken, _amount);
		Transfers._pushFunds(reserveToken, _from, _amount);
	}

	function recoverLostFunds(address _token) external onlyOwner nonReentrant
	{
		require(_token != interestToken, "invalid token");
		Wrapping._wrap(reserveToken, address(this).balance);
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
	}

	function setDev(address _newDev) external onlyOwner nonReentrant
	{
		require(_newDev != address(0), "invalid address");
		address _oldDev = dev;
		dev = _newDev;
		emit ChangeDev(_oldDev, _newDev);
	}

	function setTreasury(address _newTreasury) external onlyOwner nonReentrant
	{
		require(_newTreasury != address(0), "invalid address");
		address _oldTreasury = treasury;
		treasury = _newTreasury;
		emit ChangeTreasury(_oldTreasury, _newTreasury);
	}

	function setBuyback(address _newBuyback) external onlyOwner nonReentrant
	{
		require(_newBuyback != address(0), "invalid address");
		address _oldBuyback = buyback;
		buyback = _newBuyback;
		emit ChangeBuyback(_oldBuyback, _newBuyback);
	}

	function setDepositFee(uint256 _newDepositFee) external onlyOwner nonReentrant
	{
		require(_newDepositFee <= MAXIMUM_DEPOSIT_FEE, "invalid rate");
		uint256 _oldDepositFee = depositFee;
		depositFee = _newDepositFee;
		emit ChangeDepositFee(_oldDepositFee, _newDepositFee);
	}

	function _calcSharesFromAmount(uint256 _amount) internal view returns (uint256 _devAmount, uint256 _buybackAmount, uint256 _netAmount, uint256 _shares)
	{
		uint256 _feeAmount = _amount.mul(depositFee) / 1e18;
		_devAmount = (_feeAmount * DEPOSIT_FEE_DEV_SHARE) / 1e18;
		_buybackAmount = _feeAmount - _devAmount;
		_netAmount = _amount - _feeAmount;
		_shares = _netAmount.mul(totalSupply()) / totalReserve();
		return (_devAmount, _buybackAmount, _netAmount, _shares);
	}

	function _calcAmountFromShares(uint256 _shares) internal view returns (uint256 _amount)
	{
		return _shares.mul(totalReserve()) / totalSupply();
	}

	function _calcUnderlyingSharesFromUnderlyingAmount(uint256 _underlyingAmount) internal view returns (uint256 _underlyingShares)
	{
		return _underlyingAmount.mul(Bank(interestToken).totalSupply()) / Bank(interestToken).totalBNB();
	}

	function _calcUnderlyingAmountFromUnderlyingShares(uint256 _underlyingShares) internal view returns (uint256 _underlyingAmount)
	{
		return _underlyingShares.mul(Bank(interestToken).totalBNB()) / Bank(interestToken).totalSupply();
	}

	receive() external payable
	{
		require(msg.sender == reserveToken || msg.sender == interestToken, "not allowed"); // not to be used directly
	}

	event ChangeDev(address _oldDev, address _newDev);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeBuyback(address _oldBuyback, address _newBuyback);
	event ChangeDepositFee(uint256 _oldDepositFee, uint256 _newDepositFee);
}
