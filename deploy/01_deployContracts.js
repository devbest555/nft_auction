const { network } = require("hardhat");
module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
console.log("==deployer::", deployer);
  let nftAuction = await deploy("NFTAuction", {
    from: deployer,
    log: true,
    skipIfAlreadyDeployed: true,
  });
  let erc20 = await deploy("ERC20MockContract", {
    from: deployer,
    log: true,
    args: ["Mock ERC20", "MERC"],
    skipIfAlreadyDeployed: true,
  });

  let erc721 = await deploy("ERC721MockContract", {
    from: deployer,
    args: ["Mock NFT", "MNFT"],
    log: true,
    skipIfAlreadyDeployed: true,
  });
};
module.exports.tags = ["all", "Auction"];
