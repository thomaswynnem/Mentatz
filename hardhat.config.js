require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.28",
  networks: {
    mainnet: {
      url: process.env.AlCHEMY_API_URL,
      accounts: [process.env.PRIVATE_ADDRESS],
    },
  },
};
