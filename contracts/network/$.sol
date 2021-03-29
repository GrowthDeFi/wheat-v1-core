// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

/**
 * @dev This library is provided for convenience. It is the single source for
 *      the current network and all related hardcoded contract addresses.
 */
library $
{
	enum Network {
		Mainnet, Ropsten, Rinkeby, Kovan, Goerli,
		Bscmain, Bsctest,
		Ftmmain, Ftmtest
	}

	Network constant NETWORK = Network.Mainnet;

	function chainId() internal pure returns (uint256 _chainid)
	{
		assembly { _chainid := chainid() }
		return _chainid;
	}

	function network() internal pure returns (Network _network)
	{
		uint256 _chainid = chainId();
		if (_chainid == 1) return Network.Mainnet;
		if (_chainid == 3) return Network.Ropsten;
		if (_chainid == 4) return Network.Rinkeby;
		if (_chainid == 42) return Network.Kovan;
		if (_chainid == 5) return Network.Goerli;
		if (_chainid == 56) return Network.Bscmain;
		if (_chainid == 97) return Network.Bsctest;
		if (_chainid == 250) return Network.Ftmmain;
		if (_chainid == 4002) return Network.Ftmtest;
		require(false, "unsupported network");
	}

	address constant UniswapV2_Compatible_ROUTER02 =
		// Ethereum / UniswapV2
		NETWORK == Network.Mainnet ? 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D :
		NETWORK == Network.Ropsten ? 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D :
		NETWORK == Network.Rinkeby ? 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D :
		NETWORK == Network.Kovan ? 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D :
		NETWORK == Network.Goerli ? 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D :
		// Binance Smart Chain / PancakeSwap
		NETWORK == Network.Bscmain ? 0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F :
		NETWORK == Network.Bsctest ? 0x59870703523f8E67dE3c018FdA61C00732f2318E :
		// Fantom Opera / fUNI
		// NETWORK == Network.Ftmmain ? 0x0000000000000000000000000000000000000000 :
		// NETWORK == Network.Ftmtest ? 0x0000000000000000000000000000000000000000 :
		0x0000000000000000000000000000000000000000;

	address constant PancakeSwap_MASTERCHEF =
		// Ethereum
		// NETWORK == Network.Mainnet ? 0x0000000000000000000000000000000000000000 :
		// NETWORK == Network.Ropsten ? 0x0000000000000000000000000000000000000000 :
		// NETWORK == Network.Rinkeby ? 0x0000000000000000000000000000000000000000 :
		// NETWORK == Network.Kovan ? 0x0000000000000000000000000000000000000000 :
		// NETWORK == Network.Goerli ? 0x0000000000000000000000000000000000000000 :
		// Binance Smart Chain
		NETWORK == Network.Bscmain ? 0x73feaa1eE314F8c655E354234017bE2193C9E24E :
		NETWORK == Network.Bsctest ? 0x0000000000000000000000000000000000000000 :
		// Fantom Opera
		// NETWORK == Network.Ftmmain ? 0x0000000000000000000000000000000000000000 :
		// NETWORK == Network.Ftmtest ? 0x0000000000000000000000000000000000000000 :
		0x0000000000000000000000000000000000000000;

	address constant WBNB =
		// Ethereum
		// NETWORK == Network.Mainnet ? 0x0000000000000000000000000000000000000000 :
		// NETWORK == Network.Ropsten ? 0x0000000000000000000000000000000000000000 :
		// NETWORK == Network.Rinkeby ? 0x0000000000000000000000000000000000000000 :
		// NETWORK == Network.Kovan ? 0x0000000000000000000000000000000000000000 :
		// NETWORK == Network.Goerli ? 0x0000000000000000000000000000000000000000 :
		// Binance Smart Chain
		NETWORK == Network.Bscmain ? 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c :
		NETWORK == Network.Bsctest ? 0xd21BB48C35e7021Bf387a8b259662dC06a9df984 :
		// Fantom Opera
		// NETWORK == Network.Ftmmain ? 0x0000000000000000000000000000000000000000 :
		// NETWORK == Network.Ftmtest ? 0x0000000000000000000000000000000000000000 :
		0x0000000000000000000000000000000000000000;

	address constant CAKE =
		// Ethereum
		// NETWORK == Network.Mainnet ? 0x0000000000000000000000000000000000000000 :
		// NETWORK == Network.Ropsten ? 0x0000000000000000000000000000000000000000 :
		// NETWORK == Network.Rinkeby ? 0x0000000000000000000000000000000000000000 :
		// NETWORK == Network.Kovan ? 0x0000000000000000000000000000000000000000 :
		// NETWORK == Network.Goerli ? 0x0000000000000000000000000000000000000000 :
		// Binance Smart Chain
		NETWORK == Network.Bscmain ? 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82 :
		NETWORK == Network.Bsctest ? 0x0000000000000000000000000000000000000000 :
		// Fantom Opera
		// NETWORK == Network.Ftmmain ? 0x0000000000000000000000000000000000000000 :
		// NETWORK == Network.Ftmtest ? 0x0000000000000000000000000000000000000000 :
		0x0000000000000000000000000000000000000000;
}
