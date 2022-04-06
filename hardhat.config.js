require("@nomiclabs/hardhat-waffle");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("@nomiclabs/hardhat-etherscan");
require("hardhat-deploy");
require("@nomiclabs/hardhat-ethers");
const {
  rinkebyPrivateKey,
  alchemyKey,
  etherscanApiKey,
  coinmarketCapKey,
  mnemonic
} = require("./secrets.js");

const chainIds = {
  ganache: 1337,
  goerli: 5,
  hardhat: 31337,
  kovan: 42,
  mainnet: 1,
  rinkeby: 4,
  ropsten: 3,
};

function nodeAlchemy(network) {
  const url= "https://eth-" + network + ".alchemyapi.io/v2/" + alchemyKey;
  return {
    url: url,
    accounts: { mnemonic },
    chainId: chainIds[network],
    saveDeployments: true,
  };
}
// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true,
        runs: 500,
      },
    },
  },
  gasReporter: {
    enabled: true,
    currency: "USD",
    gasPrice: 30,
    coinmarketcap: coinmarketCapKey,
  },
  namedAccounts: {
    deployer: 0,
  },

  //uncomment this and run: yarn deploy-rinkeby
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      accounts: {
        mnemonic,
      },
      chainId: chainIds.rinkeby,
      saveDeployments: true,
      forking: {
        url: "https://eth-rinkeby.alchemyapi.io/v2/khT7j5E7O7LBI-Vf53jsKg9epwhAk2uh",
      },
    },
    kovan: nodeAlchemy("kovan"),
    rinkeby: nodeAlchemy("rinkeby"),
    ropsten: nodeAlchemy('ropsten'),
    mainnet: nodeAlchemy('mainnet'),
  },
  etherscan: {
    apiKey: etherscanApiKey,
  },
  solidity: {
    compilers: [
      {
        version: '0.8.4',
        settings: {
          optimizer: {
            enabled: true,
            runs: 2000,
          },
        },
      },
    ],
  },
  mocha: {
    timeout: 200e3
  },
};
