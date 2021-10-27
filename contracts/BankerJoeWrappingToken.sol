// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";
import { DelayedActionGuard } from "./DelayedActionGuard.sol";

import { Transfers } from "./modules/Transfers.sol";
import { Wrapping } from "./modules/Wrapping.sol";

import { Joetroller, JRewardDistributor, JToken } from "./interop/BankerJoe.sol";

/**
 * @notice This contract implements a compounding strategy for BankerJoe.
 *         It basically allows depositing and withdrawing jToken funds and
 *         collects the reward/bonus token (JOE/AVAX). Rewards are converted
 *         to more of the jToken and incorporated into the reserve, after a
 *         performance fee is deducted. The bonus is also deducted in full as
 *         performance fee.
 */
contract BankerJoeWrappingToken is ERC20, ReentrancyGuard, /*WhitelistGuard,*/ DelayedActionGuard
{
	using SafeMath for uint256;

	// strategy token configuration
	address private immutable bonusToken;
	address private immutable rewardToken;
	address private immutable reserveToken;
	address private immutable underlyingToken;

	// addresses receiving tokens
	address private treasury;
	address private collector;

	/// @dev Single public function to expose the private state, saves contract space
	function state() external view returns (
		address _bonusToken,
		address _rewardToken,
		address _reserveToken,
		address _underlyingToken,
		address _treasury,
		address _collector
	)
	{
		return (
			bonusToken,
			rewardToken,
			reserveToken,
			underlyingToken,
			treasury,
			collector
		);
	}

	/**
	 * @dev Constructor for this strategy contract.
	 * @param _name The ERC-20 token name.
	 * @param _symbol The ERC-20 token symbol.
	 * @param _decimals The ERC-20 token decimals.
	 * @param _reserveToken The jToken address to be used as reserve.
	 * @param _bonusToken The token address to be collected as bonus (WAVAX).
	 * @param _treasury The treasury address used to recover lost funds.
	 * @param _collector The fee collector address to collect the performance fee.
	 */
	constructor (string memory _name, string memory _symbol, uint8 _decimals,
		address _reserveToken, address _bonusToken,
		address _treasury, address _collector)
		ERC20(_name, _symbol) public
	{
		require(_decimals == ERC20(_reserveToken).decimals(), "invalid decimals");
		_setupDecimals(_decimals);
		(address _underlyingToken,address _rewardToken) = _getTokens(_reserveToken);
		bonusToken = _bonusToken;
		rewardToken = _rewardToken;
		reserveToken = _reserveToken;
		underlyingToken = _underlyingToken;
		treasury = _treasury;
		collector = _collector;
	}

	/**
	 * @notice Provides the amount of reserve tokens currently being help by
	 *         this contract.
	 * @return _totalReserve The amount of the reserve token corresponding
	 *                       to this contract's balance.
	 */
	function totalReserve() public view returns (uint256 _totalReserve)
	{
		return totalSupply();
	}

	/**
	 * @notice Allows for the beforehand calculation of shares to be
	 *         received/minted upon depositing to the contract.
	 * @param _amount The amount of reserve token being deposited.
	 * @return _shares The amount of shares being received.
	 */
	function calcSharesFromAmount(uint256 _amount) external pure returns (uint256 _shares)
	{
		return _amount;
	}

	/**
	 * @notice Allows for the beforehand calculation of the amount of
	 *         reserve token to be withdrawn given the desired amount of
	 *         shares.
	 * @param _shares The amount of shares to provide.
	 * @return _amount The amount of the reserve token to be received.
	 */
	function calcAmountFromShares(uint256 _shares) external pure returns (uint256 _amount)
	{
		return _shares;
	}

	/**
	 * @notice Returns the amount of reward/bonus tokens pending collection.
	 * @return _rewardAmount The amount of the reward token to be collected.
	 * @return _bonusAmount The amount of the bonus token to be collected.
	 */
	function pendingReward() external view returns (uint256 _rewardAmount, uint256 _bonusAmount)
	{
		return _getPendingReward();
	}

	/**
	 * @notice Performs the minting of shares upon the deposit of the
	 *         reserve token. The actual number of shares being minted can
	 *         be calculated using the calcSharesFromAmount() function.
	 * @param _amount The amount of reserve token being deposited in the
	 *                operation.
	 */
	function deposit(uint256 _amount) external /*onlyEOAorWhitelist*/ nonReentrant
	{
		address _from = msg.sender;
		uint256 _shares = _amount;
		Transfers._pullFunds(reserveToken, _from, _amount);
		_mint(_from, _shares);
	}

	/**
	 * @notice Performs the burning of shares upon the withdrawal of
	 *         the reserve token. The actual amount of the reserve token to
	 *         be received can be calculated using the
	 *         calcAmountFromShares() function.
	 * @param _shares The amount of this shares being redeemed in the operation.
	 */
	function withdraw(uint256 _shares) external /*onlyEOAorWhitelist*/ nonReentrant
	{
		address _from = msg.sender;
		uint256 _amount = _shares;
		_burn(_from, _shares);
		Transfers._pushFunds(reserveToken, _from, _amount);
	}

	/**
	 * Performs the conversion of the accumulated reward token into more of
	 * the reserve token. This function allows the compounding of rewards.
	 * Part of the reward accumulated is collected and sent to the fee collector
	 * contract as performance fee.
	 */
	function gulp() external /*onlyEOAorWhitelist*/ nonReentrant
	{
		require(_gulp(), "unavailable");
	}

	/// @dev Actual gulp implementation
	function _gulp() internal returns (bool _success)
	{
		_claim();
		{
			uint256 _totalBonus = Transfers._getBalance(bonusToken);
			Transfers._pushFunds(bonusToken, collector, _totalBonus);
		}
		{
			uint256 _totalReward = Transfers._getBalance(rewardToken);
			Transfers._pushFunds(rewardToken, collector, _totalReward);
		}
		return true;
	}

	/**
	 * @notice Allows the recovery of tokens sent by mistake to this
	 *         contract, excluding tokens relevant to its operations.
	 *         The full balance is sent to the treasury address.
	 *         This is a privileged function.
	 * @param _token The address of the token to be recovered.
	 */
	function recoverLostFunds(address _token) external onlyOwner nonReentrant
		delayed(this.recoverLostFunds.selector, keccak256(abi.encode(_token)))
	{
		require(_token != bonusToken, "invalid token");
		require(_token != rewardToken, "invalid token");
		uint256 _balance = Transfers._getBalance(_token);
		if (_token == reserveToken) {
			_balance -= totalReserve();
		}
		Transfers._pushFunds(_token, treasury, _balance);
	}

	/**
	 * @notice Updates the treasury address used to recover lost funds.
	 *         This is a privileged function.
	 * @param _newTreasury The new treasury address.
	 */
	function setTreasury(address _newTreasury) external onlyOwner
		delayed(this.setTreasury.selector, keccak256(abi.encode(_newTreasury)))
	{
		require(_newTreasury != address(0), "invalid address");
		address _oldTreasury = treasury;
		treasury = _newTreasury;
		emit ChangeTreasury(_oldTreasury, _newTreasury);
	}

	/**
	 * @notice Updates the fee collector address used to collect the performance fee.
	 *         This is a privileged function.
	 * @param _newCollector The new fee collector address.
	 */
	function setCollector(address _newCollector) external onlyOwner
		delayed(this.setCollector.selector, keccak256(abi.encode(_newCollector)))
	{
		require(_newCollector != address(0), "invalid address");
		address _oldCollector = collector;
		collector = _newCollector;
		emit ChangeCollector(_oldCollector, _newCollector);
	}

	// ----- BEGIN: underlying contract abstraction

	/// @dev Lists the reserve and reward tokens of the lending pool
	function _getTokens(address _reserveToken) internal view returns (address _underlyingToken, address _rewardToken)
	{
		address _joetroller = JToken(_reserveToken).joetroller();
		address _distributor = Joetroller(_joetroller).rewardDistributor();
		_underlyingToken = JToken(_reserveToken).underlying();
		_rewardToken = JRewardDistributor(_distributor).joeAddress();
		return (_underlyingToken, _rewardToken);
	}

	/// @dev Retrieves the current pending reward for the lending pool
	function _getPendingReward() internal view returns (uint256 _pendingReward, uint256 _pendingBonus)
	{
		address _joetroller = JToken(reserveToken).joetroller();
		address _distributor = Joetroller(_joetroller).rewardDistributor();
		_pendingReward = JRewardDistributor(_distributor).rewardAccrued(0, address(this));
		_pendingBonus = JRewardDistributor(_distributor).rewardAccrued(1, address(this));
		return (_pendingReward, _pendingBonus);
	}

	/// @dev Claims the current pending reward for the lending pool
	function _claim() internal
	{
		address _joetroller = JToken(reserveToken).joetroller();
		address _distributor = Joetroller(_joetroller).rewardDistributor();
		address payable[] memory _accounts = new address payable[](1);
		_accounts[0] = address(this);
		address[] memory _jtokens = new address[](1);
		_jtokens[0] = reserveToken;
		JRewardDistributor(_distributor).claimReward(0, _accounts, _jtokens, false, true);
		JRewardDistributor(_distributor).claimReward(1, _accounts, _jtokens, false, true);
		Wrapping._wrap(bonusToken, address(this).balance);
	}

	// ----- END: underlying contract abstraction

	/// @dev Allows for receiving the native token
	receive() external payable
	{
	}

	// events emitted by this contract
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeCollector(address _oldCollector, address _newCollector);
}

contract BankerJoeWrappingTokenBridge
{
	using SafeMath for uint256;

	address payable public immutable strategyToken;
	address public immutable bonusToken;
	address public immutable reserveToken;
	address public immutable underlyingToken;

	constructor (address payable _strategyToken) public
	{
		(address _bonusToken,,address _reserveToken, address _underlyingToken,,) = BankerJoeWrappingToken(_strategyToken).state();
		strategyToken = _strategyToken;
		bonusToken = _bonusToken;
		reserveToken = _reserveToken;
		underlyingToken = _underlyingToken;
	}

	function calcSharesFromAmount(uint256 _amount) external view returns (uint256 _shares)
	{
		return _calcDepositAmount(_amount);
	}

	function calcAmountFromShares(uint256 _shares) external view returns (uint256 _amount)
	{
		return _calcWithdrawalAmount(_shares);
	}

	function deposit(uint256 _amount, uint256 _minShares) external
	{
		address _from = msg.sender;
		Transfers._pullFunds(underlyingToken, _from, _amount);
		_deposit(_amount);
		uint256 _value = Transfers._getBalance(reserveToken);
		Transfers._approveFunds(reserveToken, strategyToken, _value);
		BankerJoeWrappingToken(strategyToken).deposit(_value);
		uint256 _shares = Transfers._getBalance(strategyToken);
		require(_shares >= _minShares, "high slippage");
		Transfers._pushFunds(strategyToken, _from, _shares);
	}

	function withdraw(uint256 _shares, uint256 _minAmount) external
	{
		address _from = msg.sender;
		Transfers._pullFunds(strategyToken, _from, _shares);
		BankerJoeWrappingToken(strategyToken).withdraw(_shares);
		uint256 _value = Transfers._getBalance(reserveToken);
		_withdraw(_value);
		uint256 _amount = Transfers._getBalance(underlyingToken);
		require(_amount >= _minAmount, "high slippage");
		Transfers._pushFunds(underlyingToken, _from, _amount);
	}

	function depositNative(uint256 _minShares) external payable
	{
		address _from = msg.sender;
		uint256 _amount = msg.value;
		require(underlyingToken == bonusToken, "invalid operation");
		Wrapping._wrap(bonusToken, _amount);
		_deposit(_amount);
		uint256 _value = Transfers._getBalance(reserveToken);
		Transfers._approveFunds(reserveToken, strategyToken, _value);
		BankerJoeWrappingToken(strategyToken).deposit(_value);
		uint256 _shares = Transfers._getBalance(strategyToken);
		require(_shares >= _minShares, "high slippage");
		Transfers._pushFunds(strategyToken, _from, _shares);
	}

	function withdrawNative(uint256 _shares, uint256 _minAmount) external
	{
		address payable _from = msg.sender;
		require(underlyingToken == bonusToken, "invalid operation");
		Transfers._pullFunds(strategyToken, _from, _shares);
		BankerJoeWrappingToken(strategyToken).withdraw(_shares);
		uint256 _value = Transfers._getBalance(reserveToken);
		_withdraw(_value);
		uint256 _amount = Transfers._getBalance(underlyingToken);
		require(_amount >= _minAmount, "high slippage");
		Wrapping._unwrap(bonusToken, _amount);
		_from.transfer(_amount);
	}

	// ----- BEGIN: underlying contract abstraction

	/// @dev Calculates the amount of jToken to be minted from underlying
	function _calcDepositAmount(uint256 _amount) internal view returns (uint256 _value)
	{
		uint256 _exchangeRate = JToken(reserveToken).exchangeRateStored();
		return _amount.mul(1e18).div(_exchangeRate);
	}

	/// @dev Calculates the amount of underlying upon redeemeing jToken
	function _calcWithdrawalAmount(uint256 _value) internal view returns (uint256 _amount)
	{
		uint256 _exchangeRate = JToken(reserveToken).exchangeRateStored();
		return _value.mul(_exchangeRate).div(1e18);
	}

	/// @dev Performs a deposit into the lending pool
	function _deposit(uint256 _amount) internal
	{
		Transfers._approveFunds(underlyingToken, reserveToken, _amount);
		uint256 _errorCode = JToken(reserveToken).mint(_amount);
		require(_errorCode == 0, "lend unavailable");
	}

	/// @dev Performs a withdrawal from the lending pool
	function _withdraw(uint256 _amount) internal
	{
		uint256 _errorCode = JToken(reserveToken).redeem(_amount);
		require(_errorCode == 0, "redeem unavailable");
	}

	// ----- END: underlying contract abstraction

	/// @dev Allows for receiving the native token
	receive() external payable
	{
	}
}
