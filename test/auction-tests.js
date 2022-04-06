const { expect } = require("chai");

const { BigNumber } = require("ethers");
const { network } = require("hardhat");

const tokenId = 1;
const minPrice = 10000;
const newPrice = 15000;
const buyNowPrice = 100000;
const tokenBidAmount = 25000;
const tokenAmount = 50000;
const zeroAddress = "0x0000000000000000000000000000000000000000";
const zeroERC20Tokens = 0;
const emptyFeeRecipients = [];
const emptyFeePercentages = [];

// Deploy and create a mock erc721 contract.
// Test end to end auction
describe("End to end auction tests", function () {
  let ERC721;
  let erc721;
  let NFTAuction;
  let nftAuction;
  let contractOwner;
  let user1;
  let user2;
  let user3;
  let user4;
  let bidIncreasePercentage;
  let auctionBidPeriod;
  //deploy mock erc721 token
  beforeEach(async function () {
    ERC721 = await ethers.getContractFactory("ERC721MockContract");
    NFTAuction = await ethers.getContractFactory("NFTAuction");
    [contractOwner, user1, user2, user3, user4] = await ethers.getSigners();

    erc721 = await ERC721.deploy("Mock NFT", "MNFT");
    await erc721.deployed();
    await erc721.mint(user1.address, 1);

    nftAuction = await NFTAuction.deploy();
    await nftAuction.deployed();
    //approve our smart contract to transfer this NFT
    await erc721.connect(user1).approve(nftAuction.address, 1);
  });
  
  describe("test => default auction", async function () {
    
    it("multi bids and finish auction after end period", async function () {
      bidIncreasePercentage = 1000; // 10%
      auctionBidPeriod = 86400; // 1 day
      await nftAuction.connect(user1)
        .createDefaultNftAuction(
          erc721.address,
          tokenId,
          zeroAddress,
          minPrice,
          buyNowPrice,
          emptyFeeRecipients,
          emptyFeePercentages
        );

      const nftOwner = await erc721.ownerOf(tokenId);
      console.log('[nft owner]', nftOwner, nftAuction.address, user1.address)
              
      const val = 100001;
      await nftAuction.connect(user2)
        .makeBid(erc721.address, tokenId, zeroAddress, zeroERC20Tokens, {
          value: minPrice,
        });
      const nftOwner2 = await erc721.ownerOf(tokenId);
      console.log('[nft owner 2]', nftOwner2, nftAuction.address, user2.address)
      const bidIncreaseByMinPercentage = (minPrice * (10000 + bidIncreasePercentage)) / 10000;
      await network.provider.send("evm_increaseTime", [auctionBidPeriod / 2]);
      await nftAuction.connect(user3)
        .makeBid(erc721.address, tokenId, zeroAddress, zeroERC20Tokens, {
          value: bidIncreaseByMinPercentage,
        });
      await network.provider.send("evm_increaseTime", [86000]);
      const bidIncreaseByMinPercentage2 = (bidIncreaseByMinPercentage * (10000 + bidIncreasePercentage)) / 10000;
      await nftAuction.connect(user2)
        .makeBid(erc721.address, tokenId, zeroAddress, zeroERC20Tokens, {
          value: bidIncreaseByMinPercentage2,
        });
      await network.provider.send("evm_increaseTime", [86001]);
      const bidIncreaseByMinPercentage3 = (bidIncreaseByMinPercentage2 * (10000 + bidIncreasePercentage)) / 10000;
      await nftAuction.connect(user3)
        .makeBid(erc721.address, tokenId, zeroAddress, zeroERC20Tokens, {
          value: bidIncreaseByMinPercentage3,
        });
      //should not be able to settle auction yet
      await expect(
        nftAuction.connect(user3).settleAuction(erc721.address, tokenId)
      ).to.be.revertedWith("Auction is not yet over");
      await network.provider.send("evm_increaseTime", [auctionBidPeriod + 1]);
      //auction has ended
      await nftAuction.connect(user3).settleAuction(erc721.address, tokenId);
      expect(await erc721.ownerOf(tokenId)).to.equal(user3.address);
    });
  });
  describe("test => custom auction", async function () {
    bidIncreasePercentage = 2000;
    auctionBidPeriod = 106400;
    beforeEach(async function () {
      await nftAuction
        .connect(user1)
        .createNewNftAuction(
          erc721.address,
          tokenId,
          zeroAddress,
          minPrice,
          buyNowPrice,
          auctionBidPeriod,
          bidIncreasePercentage,
          emptyFeeRecipients,
          emptyFeePercentages
        );
    });
    it("multi bids and finish auction after end period", async function () {
      nftAuction.connect(user2)
        .makeBid(erc721.address, tokenId, zeroAddress, zeroERC20Tokens, {
          value: minPrice,
        });
      const bidIncreaseByMinPercentage = (minPrice * (10000 + bidIncreasePercentage)) / 10000;
      await network.provider.send("evm_increaseTime", [43200]);

      await nftAuction.connect(user3)
        .makeBid(erc721.address, tokenId, zeroAddress, zeroERC20Tokens, {
          value: bidIncreaseByMinPercentage,
        });
      await expect(
        nftAuction.connect(user1).updateMinimumPrice(erc721.address, tokenId, newPrice)
      ).to.be.revertedWith("The auction has a valid bid made");

      await network.provider.send("evm_increaseTime", [86000]);
      const bidIncreaseByMinPercentage2 = (bidIncreaseByMinPercentage * (10000 + bidIncreasePercentage)) / 10000;
      await nftAuction.connect(user2)
        .makeBid(erc721.address, tokenId, zeroAddress, zeroERC20Tokens, {
          value: bidIncreaseByMinPercentage2,
        });
      await network.provider.send("evm_increaseTime", [86001]);
      const bidIncreaseByMinPercentage3 = (bidIncreaseByMinPercentage2 * (10000 + bidIncreasePercentage)) / 10000;
      await nftAuction.connect(user3)
        .makeBid(erc721.address, tokenId, zeroAddress, zeroERC20Tokens, {
          value: bidIncreaseByMinPercentage3,
        });
      //should not be able to settle auction yet
      await expect(
        nftAuction.connect(user3).settleAuction(erc721.address, tokenId)
      ).to.be.revertedWith("Auction is not yet over");
      await network.provider.send("evm_increaseTime", [auctionBidPeriod + 1]);
      //auction has ended

      await nftAuction.connect(user3).settleAuction(erc721.address, tokenId);
      expect(await erc721.ownerOf(tokenId)).to.equal(user3.address);
    });
  });
  describe("test => early bid auction", async function () {
    bidIncreasePercentage = 2000;
    auctionBidPeriod = 106400;
    beforeEach(async function () {
      await nftAuction
        .connect(user2)
        .makeBid(erc721.address, tokenId, zeroAddress, zeroERC20Tokens, {
          value: minPrice - 1,
        });
    });
    it("owner create auction which finish after multi bids", async function () {
      await nftAuction
        .connect(user1)
        .createNewNftAuction(
          erc721.address,
          tokenId,
          zeroAddress,
          minPrice,
          buyNowPrice,
          auctionBidPeriod,
          bidIncreasePercentage,
          emptyFeeRecipients,
          emptyFeePercentages
        );

      await expect(
        nftAuction
          .connect(user2)
          .makeBid(erc721.address, tokenId, zeroAddress, zeroERC20Tokens, {
            value: minPrice,
          })
      ).to.be.revertedWith("Not enough funds to bid on NFT");

      const bidIncreaseByMinPercentage =
        (minPrice * (10000 + bidIncreasePercentage)) / 10000;
      await network.provider.send("evm_increaseTime", [43200]);
      await nftAuction
        .connect(user3)
        .makeBid(erc721.address, tokenId, zeroAddress, zeroERC20Tokens, {
          value: bidIncreaseByMinPercentage,
        });
      await network.provider.send("evm_increaseTime", [86000]);
      const bidIncreaseByMinPercentage2 =
        (bidIncreaseByMinPercentage * (10000 + bidIncreasePercentage)) / 10000;
      await nftAuction
        .connect(user2)
        .makeBid(erc721.address, tokenId, zeroAddress, zeroERC20Tokens, {
          value: bidIncreaseByMinPercentage2,
        });
      await network.provider.send("evm_increaseTime", [86001]);
      const bidIncreaseByMinPercentage3 = (bidIncreaseByMinPercentage2 * (10000 + bidIncreasePercentage)) / 10000;
      await nftAuction
        .connect(user3)
        .makeBid(erc721.address, tokenId, zeroAddress, zeroERC20Tokens, {
          value: bidIncreaseByMinPercentage3,
        });
      //should not be able to settle auction yet
      await expect(
        nftAuction.connect(user3).settleAuction(erc721.address, tokenId)
      ).to.be.revertedWith("Auction is not yet over");
      await network.provider.send("evm_increaseTime", [auctionBidPeriod + 1]);
      //auction has ended
      await nftAuction.connect(user3).settleAuction(erc721.address, tokenId);
      expect(await erc721.ownerOf(tokenId)).to.equal(user3.address);
    });
  });
  
  describe("test => ERC20 auction", async function () {
    it("multi bids and finish auction after end period", async function () {
      bidIncreasePercentage = 1000;
      auctionBidPeriod = 86400;
      ERC20 = await ethers.getContractFactory("ERC20MockContract");

      erc20 = await ERC20.deploy("Mock ERC20", "MERC");
      await erc20.deployed();
      await erc20.mint(user1.address, tokenAmount);
      await erc20.mint(user2.address, tokenAmount);

      await erc20.mint(user3.address, tokenAmount);

      otherErc20 = await ERC20.deploy("OtherToken", "OTK");
      await otherErc20.deployed();

      await otherErc20.mint(user3.address, tokenAmount);

      await erc20.connect(user1).approve(nftAuction.address, tokenAmount);
      await erc20.connect(user2).approve(nftAuction.address, tokenBidAmount);
      await erc20.connect(user3).approve(nftAuction.address, tokenAmount);
      await otherErc20.connect(user3).approve(nftAuction.address, tokenAmount);

      await nftAuction.connect(user1)
        .createDefaultNftAuction(
          erc721.address,
          tokenId,
          erc20.address,
          minPrice,
          buyNowPrice,
          emptyFeeRecipients,
          emptyFeePercentages
        );

      await nftAuction.connect(user2).makeBid(erc721.address, tokenId, erc20.address, minPrice);
      const bidIncreaseByMinPercentage = (minPrice * (10000 + bidIncreasePercentage)) / 10000;
      await network.provider.send("evm_increaseTime", [auctionBidPeriod / 2]);

      await nftAuction.connect(user3).makeBid(erc721.address, tokenId, erc20.address, bidIncreaseByMinPercentage);
      await network.provider.send("evm_increaseTime", [86000]);

      const bidIncreaseByMinPercentage2 = (bidIncreaseByMinPercentage * (10000 + bidIncreasePercentage)) / 10000;
      await nftAuction.connect(user2).makeBid(erc721.address, tokenId, erc20.address, bidIncreaseByMinPercentage2);
      await network.provider.send("evm_increaseTime", [86001]);
      
      const bidIncreaseByMinPercentage3 = (bidIncreaseByMinPercentage2 * (10000 + bidIncreasePercentage)) / 10000;
      await nftAuction.connect(user3).makeBid(erc721.address, tokenId, erc20.address, bidIncreaseByMinPercentage3);

      //should not be able to settle auction yet
      await expect(
        nftAuction.connect(user3).settleAuction(erc721.address, tokenId)
      ).to.be.revertedWith("Auction is not yet over");
      await network.provider.send("evm_increaseTime", [auctionBidPeriod + 1]);

      //auction has ended
      await nftAuction.connect(user3).settleAuction(erc721.address, tokenId);
      expect(await erc721.ownerOf(tokenId)).to.equal(user3.address);
    });
  });

});
