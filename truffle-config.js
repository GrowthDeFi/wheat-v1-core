require('dotenv').config();
const HDWalletProvider = require('@truffle/hdwallet-provider');
const gasLimit = process.env['GAS_LIMIT'];
const gasPrice = process.env['GAS_PRICE'];
const privateKey = process.env['PRIVATE_KEY'];
const ankrProjectId = process.env['ANKR_PROJECT_ID'];
const ankrApikeyBscmain = process.env['ANKR_APIKEY_BSCMAIN'];
const ankrApikeyBsctest = process.env['ANKR_APIKEY_BSCTEST'];
const infuraProjectId = process.env['INFURA_PROJECT_ID'];

module.exports = {
  compilers: {
    solc: {
      version: '0.6.12',
      optimizer: {
        enabled: false,
        runs: 200,
      },
    },
  },
  networks: {
    mainnet: {
      network_id: 1,
      gasPrice,
      networkCheckTimeout: 10000, // fixes truffle bug
      provider: () => new HDWalletProvider(privateKey, 'https://mainnet.infura.io/v3/' + infuraProjectId),
    },
    ropsten: {
      network_id: 3,
      networkCheckTimeout: 10000, // fixes truffle bug
      provider: () => new HDWalletProvider(privateKey, 'https://ropsten.infura.io/v3/' + infuraProjectId),
      skipDryRun: true,
    },
    rinkeby: {
      network_id: 4,
      networkCheckTimeout: 10000, // fixes truffle bug
      provider: () => new HDWalletProvider(privateKey, 'https://rinkeby.infura.io/v3/' + infuraProjectId),
      skipDryRun: true,
    },
    kovan: {
      network_id: 42,
      networkCheckTimeout: 10000, // fixes truffle bug
      provider: () => new HDWalletProvider(privateKey, 'https://kovan.infura.io/v3/' + infuraProjectId),
      skipDryRun: true,
    },
    goerli: {
      network_id: 5,
      networkCheckTimeout: 10000, // fixes truffle bug
      provider: () => new HDWalletProvider(privateKey, 'https://goerli.infura.io/v3/' + infuraProjectId),
      skipDryRun: true,
    },
    bscmain: {
      network_id: 56,
      gasPrice,
      networkCheckTimeout: 10000, // fixes truffle bug
      // provider: () => new HDWalletProvider(privateKey, 'https://apis.ankr.com/' + ankrApikeyBscmain + '/' + ankrProjectId + '/binance/full/main'),
      provider: () => new HDWalletProvider(privateKey, 'https://bsc-dataseed.binance.org/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://bsc-dataseed1.defibit.io/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://bsc-dataseed1.ninicoin.io/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://bsc-dataseed2.defibit.io/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://bsc-dataseed3.defibit.io/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://bsc-dataseed4.defibit.io/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://bsc-dataseed2.ninicoin.io/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://bsc-dataseed3.ninicoin.io/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://bsc-dataseed4.ninicoin.io/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://bsc-dataseed1.binance.org/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://bsc-dataseed2.binance.org/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://bsc-dataseed3.binance.org/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://bsc-dataseed4.binance.org/'),
    },
    bsctest: {
      network_id: 97,
      networkCheckTimeout: 10000, // fixes truffle bug
      // provider: () => new HDWalletProvider(privateKey, 'https://apis.ankr.com/' + ankrApikeyBsctest + '/' + ankrProjectId + '/binance/full/test'),
      provider: () => new HDWalletProvider(privateKey, 'https://data-seed-prebsc-1-s1.binance.org:8545/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://data-seed-prebsc-2-s1.binance.org:8545/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://data-seed-prebsc-1-s2.binance.org:8545/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://data-seed-prebsc-2-s2.binance.org:8545/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://data-seed-prebsc-1-s3.binance.org:8545/'),
      // provider: () => new HDWalletProvider(privateKey, 'https://data-seed-prebsc-2-s3.binance.org:8545/'),
      skipDryRun: true,
    },
    ftmmain: {
      network_id: 250,
      gasPrice,
      networkCheckTimeout: 10000, // fixes truffle bug
      provider: () => new HDWalletProvider(privateKey, 'https://rpcapi.fantom.network/'),
    },
    ftmtest: {
      network_id: 4002,
      networkCheckTimeout: 10000, // fixes truffle bug
      provider: () => new HDWalletProvider(privateKey, 'https://rpc.testnet.fantom.network/'),
      skipDryRun: true,
    },
    development: {
      network_id: '*',
      gas: gasLimit,
      host: 'localhost',
      port: 8545,
      skipDryRun: true,
    },
  },
};
