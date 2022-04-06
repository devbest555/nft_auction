//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.4;

/// @title NFTAuction Interface
interface INFTAuction {
        
    function createDefaultNftAuction(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _minPrice,
        uint128 _buyNowPrice,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    ) external;

    function createNewNftAuction(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _minPrice,
        uint128 _buyNowPrice,
        uint32 _auctionBidPeriod, //this is the time that the auction lasts until another bid occurs
        uint32 _bidIncreasePercentage,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    ) external;

    function createSale(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _buyNowPrice,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    ) external;

    function makeBid(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _tokenAmount
    ) external payable;

    function withdrawBid(address _nftContractAddress, uint256 _tokenId) external;

    function settleAuction(address _nftContractAddress, uint256 _tokenId) external;

    function withdrawAuction(address _nftContractAddress, uint256 _tokenId) external;

    function updateMinimumPrice(
        address _nftContractAddress,
        uint256 _tokenId,
        uint128 _newMinPrice
    ) external;

    function updateBuyNowPrice(
        address _nftContractAddress,
        uint256 _tokenId,
        uint128 _newBuyNowPrice
    ) external;

    function takeHighestBid(address _nftContractAddress, uint256 _tokenId) external;

    function ownerOfNFT(address _nftContractAddress, uint256 _tokenId) external view returns (address);

    function withdrawAllFailedCredits() external;
}