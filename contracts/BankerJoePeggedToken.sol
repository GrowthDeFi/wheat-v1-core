// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { DelayedActionGuard } from "./DelayedActionGuard.sol";

import { Transfers } from "./modules/Transfers.sol";
import { Wrapping } from "./modules/Wrapping.sol";

import { Joetroller, JRewardDistributor, JToken } from "./interop/BankerJoe.sol";
import { PSM } from "./interop/Mor.sol";

contract BankerJoePeggedToken is ERC20, ReentrancyGuard, DelayedActionGuard
{
	// strategy token configuration
	address private immutable bonusToken;
	address private immutable rewardToken;
	address private immutable reserveToken;
	address private immutable stakingToken;

	// addresses receiving tokens
	address private psm;
	address private treasury;
	address private collector;

	constructor (string memory _name, string memory _symbol, uint8 _decimals,
		address _stakingToken, address _bonusToken,
		address _psm, address _treasury, address _collector)
		ERC20(_name, _symbol) public
	{
		(address _reserveToken, address _rewardToken) = _getTokens(_stakingToken);
		require(_decimals == ERC20(_reserveToken).decimals(), "invalid decimals");
		_setupDecimals(_decimals);
		bonusToken = _bonusToken;
		rewardToken = _rewardToken;
		reserveToken = _reserveToken;
		stakingToken = _stakingToken;
		psm = _psm;
		treasury = _treasury;
		collector = _collector;
	}

	/// @dev Single public function to expose the private state, saves contract space
	function state() external view returns (
		address _bonusToken,
		address _rewardToken,
		address _reserveToken,
		address _stakingToken,
		address _psm,
		address _treasury,
		address _collector
	)
	{
		return (
			bonusToken,
			rewardToken,
			reserveToken,
			stakingToken,
			psm,
			treasury,
			collector
		);
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
	 * @return _shares The net amount of shares being received.
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
	 * @notice Performs the minting of shares upon the deposit of the
	 *         reserve token.
	 * @param _amount The amount of reserve token being deposited in the
	 *                operation.
	 */
	function deposit(uint256 _amount) external nonReentrant
	{
		address _from = msg.sender;
		uint256 _shares = _amount;
		Transfers._pullFunds(reserveToken, _from, _amount);
		_deposit(_amount);
		_mint(_from, _shares);
	}

	/**
	 * @notice Performs the burning of shares upon the withdrawal of
	 *         the reserve token.
	 * @param _shares The amount of this shares being redeemed in the operation.
	 */
	function withdraw(uint256 _shares) external nonReentrant
	{
		address _from = msg.sender;
		uint256 _amount = _shares;
		_burn(_from, _shares);
		_withdraw(_amount);
		Transfers._pushFunds(reserveToken, _from, _amount);
	}

	/**
	 * Deposits excess reserve into the PSM and sends reward/bonus tokens to the collector.
	 */
	function gulp() external nonReentrant
	{
		require(_gulp(), "unavailable");
	}

	/// @dev Actual gulp implementation
	function _gulp() internal returns (bool _success)
	{
		uint256 _balance = _getBalance();
		uint256 _supply = totalSupply();
		if (_balance > _supply) {
			uint256 _excess = _balance - _supply;
			if (psm == address(0)) {
				_mint(treasury, _excess);
			} else {
				_mint(address(this), _excess);
				Transfers._approveFunds(address(this), PSM(psm).gemJoin(), _excess);
				PSM(psm).sellGem(treasury, _excess);
			}
		}
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
		require(_token != stakingToken, "invalid token");
		uint256 _balance = Transfers._getBalance(_token);
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

	/**
	 * @notice Updates the peg stability module address used to collect
	 *         lending fees. This is a privileged function.
	 * @param _newPsm The new peg stability module address.
	 */
	function setPsm(address _newPsm) external onlyOwner
		delayed(this.setPsm.selector, keccak256(abi.encode(_newPsm)))
	{
		address _oldPsm = psm;
		psm = _newPsm;
		emit ChangePsm(_oldPsm, _newPsm);
	}

	// ----- BEGIN: underlying contract abstraction

	/// @dev Lists the reserve and reward tokens of the lending pool
	function _getTokens(address _stakingToken) internal view returns (address _reserveToken, address _rewardToken)
	{
		address _joetroller = JToken(_stakingToken).joetroller();
		address _distributor = Joetroller(_joetroller).rewardDistributor();
		_reserveToken = JToken(_stakingToken).underlying();
		_rewardToken = JRewardDistributor(_distributor).joeAddress();
		return (_reserveToken, _rewardToken);
	}

	/// @dev Retrieves the underlying balance on the lending pool
	function _getBalance() internal returns (uint256 _amount)
	{
		return JToken(stakingToken).balanceOfUnderlying(address(this));
	}

	/// @dev Performs a deposit into the lending pool
	function _deposit(uint256 _amount) internal
	{
		Transfers._approveFunds(reserveToken, stakingToken, _amount);
		uint256 _errorCode = JToken(stakingToken).mint(_amount);
		require(_errorCode == 0, "lend unavailable");
	}

	/// @dev Performs an withdrawal from the lending pool
	function _withdraw(uint256 _amount) internal
	{
		uint256 _errorCode = JToken(stakingToken).redeemUnderlying(_amount);
		require(_errorCode == 0, "redeem unavailable");
	}

	/// @dev Claims the current pending reward for the lending pool
	function _claim() internal
	{
		address _joetroller = JToken(stakingToken).joetroller();
		address _distributor = Joetroller(_joetroller).rewardDistributor();
		address payable[] memory _accounts = new address payable[](1);
		_accounts[0] = address(this);
		address[] memory _jtokens = new address[](1);
		_jtokens[0] = stakingToken;
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
	event ChangePsm(address _oldPsm, address _newPsm);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeCollector(address _oldCollector, address _newCollector);
}

contract BankerJoePeggedTokenPSMBridge is PSM
{
	address payable public immutable strategyToken;
	address public immutable reserveToken;
	address public immutable psm;
	address public immutable override dai;
	address public immutable override gemJoin;

	constructor (address payable _strategyToken) public
	{
		(,,address _reserveToken,, address _psm,,) = BankerJoePeggedToken(_strategyToken).state();
		address _dai = PSM(_psm).dai();
		address _gemJoin = PSM(_psm).gemJoin();
		strategyToken = _strategyToken;
		reserveToken = _reserveToken;
		psm = _psm;
		dai = _dai;
		gemJoin = _gemJoin;
	}

	function tout() external override view returns (uint256 _tout)
	{
		return PSM(psm).tout();
	}

	function sellGem(address _to, uint256 _amount) external override
	{
		address _from = msg.sender;
		Transfers._pullFunds(reserveToken, _from, _amount);
		Transfers._approveFunds(reserveToken, strategyToken, _amount);
		BankerJoePeggedToken(strategyToken).deposit(_amount);
		Transfers._approveFunds(strategyToken, gemJoin, _amount);
		PSM(psm).sellGem(_to, _amount);
	}

	function buyGem(address _to, uint256 _amount) external override
	{
		address _from = msg.sender;
		uint256 _daiAmount = IERC20(dai).balanceOf(_from);
		uint256 _daiAllowance = IERC20(dai).allowance(_from, address(this));
		if (_daiAllowance < _daiAmount) _daiAmount = _daiAllowance;
		Transfers._pullFunds(dai, _from, _daiAmount);
		Transfers._approveFunds(dai, psm, _daiAmount);
		PSM(psm).buyGem(address(this), _amount);
		Transfers._approveFunds(dai, psm, 0);
		Transfers._pushFunds(dai, _from, Transfers._getBalance(dai));
		BankerJoePeggedToken(strategyToken).withdraw(_amount);		
		Transfers._pushFunds(reserveToken, _to, _amount);
	}
}
