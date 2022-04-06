//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./INFTAuction.sol";

/// @title An Auction Contract for bidding and selling single and batched NFTs
contract NFTAuction is INFTAuction {
    mapping(address => mapping(uint256 => Auction)) public nftAuctions;
    mapping(address => uint256) failedTransferCredits;

    //Each Auction is unique to each NFT (contract, id pairing).
    struct Auction {
        uint32 bidIncreasePercentage; //Bid increment in percent
        uint32 auctionBidPeriod; //Increments the length of time the auction is open in which a new bid can be made after each bid.
        uint64 auctionEnd;
        uint128 minPrice; //Reserve Price
        uint128 buyNowPrice;
        uint128 nftHighestBid;
        address nftHighestBidder;
        address nftSeller; //Seller wallet address
        address ERC20Token; // The seller can specify an ERC20 token that can be used to bid or purchase the NFT.
        address[] feeRecipients;
        uint32[] feePercentages;
    }
    
    //Default values that are used if not specified by the NFT seller.
    uint32 public defaultBidIncreasePercentage;
    uint32 public defaultAuctionBidPeriod;

    event NftAuctionCreated(
        address nftContractAddress,
        uint256 tokenId,
        address nftSeller,
        address erc20Token,
        uint128 minPrice,
        uint128 buyNowPrice,
        uint32 auctionBidPeriod,
        uint32 bidIncreasePercentage,
        address[] feeRecipients,
        uint32[] feePercentages
    );

    event SaleCreated(
        address nftContractAddress,
        uint256 tokenId,
        address nftSeller,
        address erc20Token,
        uint128 buyNowPrice,
        address[] feeRecipients,
        uint32[] feePercentages
    );

    event BidMade(
        address nftContractAddress,
        uint256 tokenId,
        address bidder,
        uint256 ethAmount,
        address erc20Token,
        uint256 tokenAmount
    );

    event AuctionPeriodUpdated(
        address nftContractAddress,
        uint256 tokenId,
        uint64 auctionEndPeriod
    );

    event NFTTransferredAndSellerPaid(
        address nftContractAddress,
        uint256 tokenId,
        address nftSeller,
        uint128 nftHighestBid,
        address nftHighestBidder
    );

    event AuctionSettled(
        address nftContractAddress,
        uint256 tokenId,
        address auctionSettler
    );

    event AuctionWithdrawn(
        address nftContractAddress,
        uint256 tokenId,
        address nftOwner
    );

    event BidWithdrawn(
        address nftContractAddress,
        uint256 tokenId,
        address highestBidder
    );

    event MinimumPriceUpdated(
        address nftContractAddress,
        uint256 tokenId,
        uint256 newMinPrice
    );

    event BuyNowPriceUpdated(
        address nftContractAddress,
        uint256 tokenId,
        uint128 newBuyNowPrice
    );

    event HighestBidTaken(address nftContractAddress, uint256 tokenId);

    // ******************** 
    // modifier
    modifier isAuctionNotStartedByOwner(
        address _nftContractAddress,
        uint256 _tokenId
    ) {
        require(
            nftAuctions[_nftContractAddress][_tokenId].nftSeller != msg.sender, "Auction already started by owner"
        );

        if (nftAuctions[_nftContractAddress][_tokenId].nftSeller != address(0)) {
            require(
                msg.sender == IERC721(_nftContractAddress).ownerOf(_tokenId), "Sender doesn't own NFT"
            );
        }

        _resetAuction(_nftContractAddress, _tokenId);
        _;
    }

    modifier auctionOngoing(address _nftContractAddress, uint256 _tokenId) {
        require(
            _isAuctionOngoing(_nftContractAddress, _tokenId), "Auction has ended"
        );
        _;
    }

    modifier priceGreaterThanZero(uint256 _price) {
        require(_price > 0, "Price cannot be 0");
        _;
    }

    modifier notNftSeller(address _nftContractAddress, uint256 _tokenId) {
        require(
            msg.sender != nftAuctions[_nftContractAddress][_tokenId].nftSeller, "Owner cannot bid on own NFT"
        );
        _;
    }
    modifier onlyNftSeller(address _nftContractAddress, uint256 _tokenId) {
        require(
            msg.sender == nftAuctions[_nftContractAddress][_tokenId].nftSeller, "Only nft seller"
        );
        _;
    }
    /*
     * The bid amount was either equal the buyNowPrice or it must be higher than the previous
     * bid by the specified bid increase percentage.
     */
    modifier bidAmountMeetsBidRequirements(
        address _nftContractAddress,
        uint256 _tokenId,
        uint128 _tokenAmount
    ) {
        require(
            _doesBidMeetBidRequirements(_nftContractAddress, _tokenId, _tokenAmount), "Not enough funds to bid on NFT"
        );
        _;
    }

    modifier minimumBidNotMade(address _nftContractAddress, uint256 _tokenId) {
        require(
            !_isMinimumBidMade(_nftContractAddress, _tokenId), "The auction has a valid bid made"
        );
        _;
    }

    /*
     * Payment is accepted if the payment is made in the ERC20 token or ETH specified by the seller.
     * Early bids on NFTs not yet up for auction must be made in ETH.
     */
    modifier paymentAccepted(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _tokenAmount
    ) {
        require(
            _isPaymentAccepted(_nftContractAddress, _tokenId, _erc20Token, _tokenAmount), "Bid to be in specified ERC20/Eth"
        );
        _;
    }

    modifier isAuctionOver(address _nftContractAddress, uint256 _tokenId) {
        require(
            !_isAuctionOngoing(_nftContractAddress, _tokenId), "Auction is not yet over"
        );
        _;
    }

    modifier notZeroAddress(address _address) {
        require(_address != address(0), "Cannot specify 0 address");
        _;
    }

    modifier isFeePercentagesLessThanMaximum(uint32[] memory _feePercentages) {
        uint32 totalPercent;
        for (uint256 i = 0; i < _feePercentages.length; i++) {
            totalPercent = totalPercent + _feePercentages[i];
        }
        require(totalPercent <= 10000, "Fee percentages exceed maximum");
        _;
    }

    modifier correctFeeRecipientsAndPercentages(
        uint256 _recipientsLength,
        uint256 _percentagesLength
    ) {
        require(
            _recipientsLength == _percentagesLength, "Recipients != percentages"
        );
        _;
    }

    modifier isNotASale(address _nftContractAddress, uint256 _tokenId) {
        require(
            !_isASale(_nftContractAddress, _tokenId), "Not applicable for a sale"
        );
        _;
    }

    /**********************************/
    // constructor
    constructor() {
        defaultBidIncreasePercentage = 100; // 1%
        defaultAuctionBidPeriod = 86400; //1 day
    }


    //AUCTION CHECK FUNCTIONS
    function _isAuctionOngoing(address _nftContractAddress, uint256 _tokenId)
        internal
        view
        returns (bool)
    {
        uint64 auctionEndTimestamp = nftAuctions[_nftContractAddress][_tokenId].auctionEnd;
        //if the auctionEnd is set to 0, the auction is technically on-going, however
        //the minimum bid price (minPrice) has not yet been met.
        return (auctionEndTimestamp == 0 || block.timestamp < auctionEndTimestamp);
    }

    /*
     * Check if a bid has been made. This is applicable in the early bid scenario
     * to ensure that if an auction is created after an early bid, the auction
     * begins appropriately or is settled if the buy now price is met.
     */
    function _isABidMade(address _nftContractAddress, uint256 _tokenId)
        internal
        view
        returns (bool)
    {
        return (nftAuctions[_nftContractAddress][_tokenId].nftHighestBid > 0);
    }

    //if the minPrice is set by the seller, check that the highest bid meets or exceeds that price.
    function _isMinimumBidMade(address _nftContractAddress, uint256 _tokenId)
        internal
        view
        returns (bool)
    {
        uint128 minPrice = nftAuctions[_nftContractAddress][_tokenId].minPrice;
        return minPrice > 0 && (nftAuctions[_nftContractAddress][_tokenId].nftHighestBid >= minPrice);
    }

    //If the buy now price is set by the seller, check that the highest bid meets that price.
    function _isBuyNowPriceMet(address _nftContractAddress, uint256 _tokenId)
        internal
        view
        returns (bool)
    {
        uint128 buyNowPrice = nftAuctions[_nftContractAddress][_tokenId].buyNowPrice;
        return buyNowPrice > 0 && nftAuctions[_nftContractAddress][_tokenId].nftHighestBid >= buyNowPrice;
    }

    /*
     * Check that a bid is applicable for the purchase of the NFT.
     * In the case of a sale: the bid needs to meet the buyNowPrice.
     * In the case of an auction: the bid needs to be a % higher than the previous bid.
     */
    function _doesBidMeetBidRequirements(
        address _nftContractAddress,
        uint256 _tokenId,
        uint128 _tokenAmount
    ) internal view returns (bool) {
        uint128 buyNowPrice = nftAuctions[_nftContractAddress][_tokenId].buyNowPrice;

        //if buyNowPrice is met, ignore increase percentage
        if (buyNowPrice > 0 && (msg.value >= buyNowPrice || _tokenAmount >= buyNowPrice)) {
            return true;
        }

        //if the NFT is up for auction, the bid needs to be a % higher than the previous bid
        uint128 nftHighestBid = nftAuctions[_nftContractAddress][_tokenId].nftHighestBid;
        uint32 bidIncreasePercentage = _getBidIncreasePercentage(_nftContractAddress, _tokenId);
        uint256 bidIncreaseAmount = (nftHighestBid * (10000 + bidIncreasePercentage)) / 10000;

        return (msg.value >= bidIncreaseAmount || _tokenAmount >= bidIncreaseAmount);
    }

    //An NFT is up for sale if the buyNowPrice is set, but the minPrice is not set.
    function _isASale(address _nftContractAddress, uint256 _tokenId)
        internal
        view
        returns (bool)
    {
        return (nftAuctions[_nftContractAddress][_tokenId].buyNowPrice > 0 &&
            nftAuctions[_nftContractAddress][_tokenId].minPrice == 0);
    }

    /**
     * Payment is accepted in the following scenarios:
     * (1) Auction already created - can accept ETH or Specified Token
     *  --------> Cannot bid with ETH & an ERC20 Token together in any circumstance<------
     * (2) Auction not created - only ETH accepted (cannot early bid with an ERC20 Token
     * (3) Cannot make a zero bid (no ETH or Token amount)
     */
    function _isPaymentAccepted(
        address _nftContractAddress,
        uint256 _tokenId,
        address _bidERC20Token,
        uint128 _tokenAmount
    ) internal view returns (bool) {
        address auctionERC20Token = nftAuctions[_nftContractAddress][_tokenId].ERC20Token;
        if (_isERC20Auction(auctionERC20Token)) {
            return msg.value == 0 && auctionERC20Token == _bidERC20Token && _tokenAmount > 0;
        } else {
            return msg.value != 0 && _bidERC20Token == address(0) && _tokenAmount == 0;
        }
    }

    function _isERC20Auction(address _auctionERC20Token)
        internal
        pure
        returns (bool)
    {
        return _auctionERC20Token != address(0);
    }

    /*
     * Returns the percentage of the total bid (used to calculate fee payments)
     */
    function _getPortionOfBid(uint256 _totalBid, uint256 _percentage)
        internal
        pure
        returns (uint256)
    {
        return (_totalBid * (_percentage)) / 10000;
    }

    /**********************************/
    //DEFAULT GETTER FUNCTIONS
    function _getBidIncreasePercentage(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal view returns (uint32) {
        uint32 bidIncreasePercentage = nftAuctions[_nftContractAddress][_tokenId].bidIncreasePercentage;

        if (bidIncreasePercentage == 0) {
            return defaultBidIncreasePercentage;
        } else {
            return bidIncreasePercentage;
        }
    }

    function _getAuctionBidPeriod(address _nftContractAddress, uint256 _tokenId)
        internal
        view
        returns (uint32)
    {
        uint32 auctionBidPeriod = nftAuctions[_nftContractAddress][_tokenId].auctionBidPeriod;

        if (auctionBidPeriod == 0) {
            return defaultAuctionBidPeriod;
        } else {
            return auctionBidPeriod;
        }
    }

    //TRANSFER NFTS TO CONTRACT  
    function _transferNftToAuctionContract(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal {
        address _nftSeller = nftAuctions[_nftContractAddress][_tokenId].nftSeller;
        if (IERC721(_nftContractAddress).ownerOf(_tokenId) == _nftSeller) {
            IERC721(_nftContractAddress).transferFrom(
                _nftSeller,
                address(this),
                _tokenId
            );
            require(IERC721(_nftContractAddress).ownerOf(_tokenId) == address(this), "nft transfer failed");
        } else {
            require(IERC721(_nftContractAddress).ownerOf(_tokenId) == address(this), "Seller doesn't own NFT");
        }
    }

    /**********************************/
    //AUCTION CREATION     

    /**
     * Setup parameters applicable to all auctions and whitelised sales:
     * -> ERC20 Token for payment (if specified by the seller) : _erc20Token
     * -> minimum price : _minPrice
     * -> buy now price : _buyNowPrice
     * -> the nft seller: msg.sender
     * -> The fee recipients & their respective percentages for a sucessful auction/sale
     */
    function _setupAuction(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _minPrice,
        uint128 _buyNowPrice,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    )
        internal
        correctFeeRecipientsAndPercentages(_feeRecipients.length, _feePercentages.length)
        isFeePercentagesLessThanMaximum(_feePercentages)
    {
        if (_erc20Token != address(0)) {
            nftAuctions[_nftContractAddress][_tokenId].ERC20Token = _erc20Token;
        }
        nftAuctions[_nftContractAddress][_tokenId].feeRecipients = _feeRecipients;
        nftAuctions[_nftContractAddress][_tokenId].feePercentages = _feePercentages;
        nftAuctions[_nftContractAddress][_tokenId].buyNowPrice = _buyNowPrice;
        nftAuctions[_nftContractAddress][_tokenId].minPrice = _minPrice;
        nftAuctions[_nftContractAddress][_tokenId].nftSeller = msg.sender;
    }

    function _createNewNftAuction(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _minPrice,
        uint128 _buyNowPrice,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    ) internal {
        // Sending the NFT to this contract
        _setupAuction(_nftContractAddress, _tokenId, _erc20Token, _minPrice, _buyNowPrice, _feeRecipients, _feePercentages);

        emit NftAuctionCreated(
            _nftContractAddress,
            _tokenId,
            msg.sender,
            _erc20Token,
            _minPrice,
            _buyNowPrice,
            _getAuctionBidPeriod(_nftContractAddress, _tokenId),
            _getBidIncreasePercentage(_nftContractAddress, _tokenId),
            _feeRecipients,
            _feePercentages
        );
        _updateOngoingAuction(_nftContractAddress, _tokenId);
    }

    /**
     * Create an auction that uses the default bid increase percentage
     * & the default auction bid period.
     */
    function createDefaultNftAuction(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _minPrice,
        uint128 _buyNowPrice,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    )
        external
        override
        isAuctionNotStartedByOwner(_nftContractAddress, _tokenId)
        priceGreaterThanZero(_minPrice)
    {
        _createNewNftAuction(_nftContractAddress, _tokenId, _erc20Token, _minPrice, _buyNowPrice, _feeRecipients, _feePercentages);
    }

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
    )
        external
        override
        isAuctionNotStartedByOwner(_nftContractAddress, _tokenId)
        priceGreaterThanZero(_minPrice)
    {
        nftAuctions[_nftContractAddress][_tokenId].auctionBidPeriod = _auctionBidPeriod;
        nftAuctions[_nftContractAddress][_tokenId].bidIncreasePercentage = _bidIncreasePercentage;
        _createNewNftAuction(_nftContractAddress, _tokenId, _erc20Token, _minPrice, _buyNowPrice, _feeRecipients, _feePercentages);
    }

    /**********************************/
    // SALES  
    function _setupSale(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _buyNowPrice,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    )
        internal
        correctFeeRecipientsAndPercentages(_feeRecipients.length, _feePercentages.length)
        isFeePercentagesLessThanMaximum(_feePercentages)
    {
        if (_erc20Token != address(0)) {
            nftAuctions[_nftContractAddress][_tokenId].ERC20Token = _erc20Token;
        }
        nftAuctions[_nftContractAddress][_tokenId].feeRecipients = _feeRecipients;
        nftAuctions[_nftContractAddress][_tokenId].feePercentages = _feePercentages;
        nftAuctions[_nftContractAddress][_tokenId].buyNowPrice = _buyNowPrice;
        nftAuctions[_nftContractAddress][_tokenId].nftSeller = msg.sender;
    }

    function createSale(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _buyNowPrice,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    )
        external
        override
        isAuctionNotStartedByOwner(_nftContractAddress, _tokenId)
        priceGreaterThanZero(_buyNowPrice)
    {
        _setupSale(_nftContractAddress, _tokenId, _erc20Token, _buyNowPrice, _feeRecipients, _feePercentages);

        emit SaleCreated(_nftContractAddress, _tokenId, msg.sender, _erc20Token, _buyNowPrice, _feeRecipients, _feePercentages);

        //check if buyNowPrice is meet and conclude sale, otherwise reverse the early bid
        if (_isABidMade(_nftContractAddress, _tokenId)) {
            if (_isBuyNowPriceMet(_nftContractAddress, _tokenId)) {
                _transferNftToAuctionContract(_nftContractAddress, _tokenId);
                _transferNftAndPaySeller(_nftContractAddress, _tokenId);
            }
        }
    }

    /**********************************/
    //BID FUNCTIONS        
    /********************************************************************
     * Make bids with ETH or an ERC20 Token specified by the NFT seller.*
     * Additionally, a buyer can pay the asking price to conclude a sale*
     * of an NFT.                                                      *
     ********************************************************************/

    function _makeBid(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _tokenAmount
    )
        internal
        notNftSeller(_nftContractAddress, _tokenId)
        paymentAccepted(_nftContractAddress, _tokenId, _erc20Token, _tokenAmount)
        bidAmountMeetsBidRequirements(_nftContractAddress, _tokenId, _tokenAmount)
    {
        _reversePreviousBidAndUpdateHighestBid(_nftContractAddress, _tokenId, _tokenAmount);

        emit BidMade(_nftContractAddress, _tokenId, msg.sender, msg.value, _erc20Token, _tokenAmount);
        _updateOngoingAuction(_nftContractAddress, _tokenId);
    }

    function makeBid(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _tokenAmount
    )
        external
        override
        payable
        auctionOngoing(_nftContractAddress, _tokenId)
    {
        _makeBid(_nftContractAddress, _tokenId, _erc20Token, _tokenAmount);
    }

    /**********************************/
    //UPDATE AUCTION         
    /***************************************************************
     * Settle an auction or sale if the buyNowPrice is met or set  *
     *  auction period to begin if the minimum price has been met. *
     ***************************************************************/
    function _updateOngoingAuction(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal {
        if (_isBuyNowPriceMet(_nftContractAddress, _tokenId)) {
            console.log("[_isBuyNowPriceMet]");
            _transferNftToAuctionContract(_nftContractAddress, _tokenId);
            _transferNftAndPaySeller(_nftContractAddress, _tokenId);
            return;
        }
        //min price not set, nft not up for auction yet
        if (_isMinimumBidMade(_nftContractAddress, _tokenId)) {
            console.log("[_isMinimumBidMade]");
            _transferNftToAuctionContract(_nftContractAddress, _tokenId);
            _updateAuctionEnd(_nftContractAddress, _tokenId);
        }
    }

    function _updateAuctionEnd(address _nftContractAddress, uint256 _tokenId)
        internal
    {
        //the auction end is always set to now + the bid period
        nftAuctions[_nftContractAddress][_tokenId].auctionEnd =
            _getAuctionBidPeriod(_nftContractAddress, _tokenId) + uint64(block.timestamp);

        emit AuctionPeriodUpdated(
            _nftContractAddress,
            _tokenId,
            nftAuctions[_nftContractAddress][_tokenId].auctionEnd
        );
    }

    /**********************************/
    //RESET FUNCTIONS        
    function _resetAuction(address _nftContractAddress, uint256 _tokenId)
        internal
    {
        nftAuctions[_nftContractAddress][_tokenId].minPrice = 0;
        nftAuctions[_nftContractAddress][_tokenId].buyNowPrice = 0;
        nftAuctions[_nftContractAddress][_tokenId].auctionEnd = 0;
        nftAuctions[_nftContractAddress][_tokenId].auctionBidPeriod = 0;
        nftAuctions[_nftContractAddress][_tokenId].bidIncreasePercentage = 0;
        nftAuctions[_nftContractAddress][_tokenId].nftSeller = address(0);
        nftAuctions[_nftContractAddress][_tokenId].ERC20Token = address(0);
    }

    // Reset all bid related parameters for an NFT.
    function _resetBids(address _nftContractAddress, uint256 _tokenId)
        internal
    {
        nftAuctions[_nftContractAddress][_tokenId].nftHighestBidder = address(0);
        nftAuctions[_nftContractAddress][_tokenId].nftHighestBid = 0;
    }

    // Internal functions that update bid parameters and reverse bids 
    function _updateHighestBid(
        address _nftContractAddress,
        uint256 _tokenId,
        uint128 _tokenAmount
    ) internal {
        address auctionERC20Token = nftAuctions[_nftContractAddress][_tokenId].ERC20Token;
        if (_isERC20Auction(auctionERC20Token)) {
            IERC20(auctionERC20Token).transferFrom(
                msg.sender,
                address(this),
                _tokenAmount
            );
            nftAuctions[_nftContractAddress][_tokenId].nftHighestBid = _tokenAmount;
        } else {
            nftAuctions[_nftContractAddress][_tokenId].nftHighestBid = uint128(msg.value);
        }
        nftAuctions[_nftContractAddress][_tokenId].nftHighestBidder = msg.sender;
    }

    function _reverseAndResetPreviousBid(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal {
        address nftHighestBidder = nftAuctions[_nftContractAddress][_tokenId].nftHighestBidder;

        uint128 nftHighestBid = nftAuctions[_nftContractAddress][_tokenId].nftHighestBid;
        _resetBids(_nftContractAddress, _tokenId);

        _payout(_nftContractAddress, _tokenId, nftHighestBidder, nftHighestBid);
    }

    function _reversePreviousBidAndUpdateHighestBid(
        address _nftContractAddress,
        uint256 _tokenId,
        uint128 _tokenAmount
    ) internal {
        address prevNftHighestBidder = nftAuctions[_nftContractAddress][_tokenId].nftHighestBidder;

        uint256 prevNftHighestBid = nftAuctions[_nftContractAddress][_tokenId].nftHighestBid;
        _updateHighestBid(_nftContractAddress, _tokenId, _tokenAmount);

        if (prevNftHighestBidder != address(0)) {
            _payout(
                _nftContractAddress,
                _tokenId,
                prevNftHighestBidder,
                prevNftHighestBid
            );
        }
    }

    //TRANSFER NFT & PAY SELLER   
    function _transferNftAndPaySeller(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal {
        address _nftSeller = nftAuctions[_nftContractAddress][_tokenId].nftSeller;
        address _nftHighestBidder = nftAuctions[_nftContractAddress][_tokenId].nftHighestBidder;
        uint128 _nftHighestBid = nftAuctions[_nftContractAddress][_tokenId].nftHighestBid;
        _resetBids(_nftContractAddress, _tokenId);

        _payFeesAndSeller(
            _nftContractAddress,
            _tokenId,
            _nftSeller,
            _nftHighestBid
        );
        IERC721(_nftContractAddress).transferFrom(
            address(this),
            _nftHighestBidder,
            _tokenId
        );

        _resetAuction(_nftContractAddress, _tokenId);

        emit NFTTransferredAndSellerPaid(
            _nftContractAddress,
            _tokenId,
            _nftSeller,
            _nftHighestBid,
            _nftHighestBidder
        );
    }

    function _payFeesAndSeller(
        address _nftContractAddress,
        uint256 _tokenId,
        address _nftSeller,
        uint256 _highestBid
    ) internal {
        uint256 feesPaid;
        for (uint256 i = 0; i < nftAuctions[_nftContractAddress][_tokenId].feeRecipients.length; i++) {
            uint256 fee = _getPortionOfBid(_highestBid, nftAuctions[_nftContractAddress][_tokenId].feePercentages[i]);
            feesPaid = feesPaid + fee;
            _payout(
                _nftContractAddress,
                _tokenId,
                nftAuctions[_nftContractAddress][_tokenId].feeRecipients[i],
                fee
            );
        }
        _payout(
            _nftContractAddress,
            _tokenId,
            _nftSeller,
            (_highestBid - feesPaid)
        );
    }

    function _payout(
        address _nftContractAddress,
        uint256 _tokenId,
        address _recipient,
        uint256 _amount
    ) internal {
        address auctionERC20Token = nftAuctions[_nftContractAddress][_tokenId].ERC20Token;

        if (_isERC20Auction(auctionERC20Token)) {
            IERC20(auctionERC20Token).transfer(_recipient, _amount);
        } else {
            // attempt to send the funds to the recipient
            (bool success, ) = payable(_recipient).call{
                value: _amount,
                gas: 20000
            }("");
            // if it failed, update their credit balance so they can pull it later
            if (!success) {
                failedTransferCredits[_recipient] = failedTransferCredits[_recipient] + _amount;
            }
        }
    }
    //SETTLE & WITHDRAW       
    function settleAuction(address _nftContractAddress, uint256 _tokenId)
        external
        override
        isAuctionOver(_nftContractAddress, _tokenId)
    {
        _transferNftAndPaySeller(_nftContractAddress, _tokenId);
        emit AuctionSettled(_nftContractAddress, _tokenId, msg.sender);
    }

    function withdrawAuction(address _nftContractAddress, uint256 _tokenId)
        external
        override
    {
        //only the NFT owner can prematurely close and auction
        require(IERC721(_nftContractAddress).ownerOf(_tokenId) == msg.sender, "Not NFT owner");

        _resetAuction(_nftContractAddress, _tokenId);

        emit AuctionWithdrawn(_nftContractAddress, _tokenId, msg.sender);
    }

    function withdrawBid(address _nftContractAddress, uint256 _tokenId)
        external
        override
        minimumBidNotMade(_nftContractAddress, _tokenId)
    {
        address nftHighestBidder = nftAuctions[_nftContractAddress][_tokenId].nftHighestBidder;
        require(msg.sender == nftHighestBidder, "Cannot withdraw funds");

        uint128 nftHighestBid = nftAuctions[_nftContractAddress][_tokenId].nftHighestBid;
        _resetBids(_nftContractAddress, _tokenId);

        _payout(_nftContractAddress, _tokenId, nftHighestBidder, nftHighestBid);

        emit BidWithdrawn(_nftContractAddress, _tokenId, msg.sender);
    }

    //UPDATE AUCTION  
    function updateMinimumPrice(
        address _nftContractAddress,
        uint256 _tokenId,
        uint128 _newMinPrice
    )
        external
        override
        onlyNftSeller(_nftContractAddress, _tokenId)
        minimumBidNotMade(_nftContractAddress, _tokenId)
        isNotASale(_nftContractAddress, _tokenId)
        priceGreaterThanZero(_newMinPrice)
    {
        nftAuctions[_nftContractAddress][_tokenId].minPrice = _newMinPrice;

        emit MinimumPriceUpdated(_nftContractAddress, _tokenId, _newMinPrice);

        if (_isMinimumBidMade(_nftContractAddress, _tokenId)) {
            _transferNftToAuctionContract(_nftContractAddress, _tokenId);
            _updateAuctionEnd(_nftContractAddress, _tokenId);
        }
    }

    function updateBuyNowPrice(
        address _nftContractAddress,
        uint256 _tokenId,
        uint128 _newBuyNowPrice
    )
        external
        override
        onlyNftSeller(_nftContractAddress, _tokenId)
        priceGreaterThanZero(_newBuyNowPrice)
    {
        nftAuctions[_nftContractAddress][_tokenId].buyNowPrice = _newBuyNowPrice;

        emit BuyNowPriceUpdated(_nftContractAddress, _tokenId, _newBuyNowPrice);

        if (_isBuyNowPriceMet(_nftContractAddress, _tokenId)) {
            _transferNftToAuctionContract(_nftContractAddress, _tokenId);
            _transferNftAndPaySeller(_nftContractAddress, _tokenId);
        }
    }

    //The NFT seller can opt to end an auction by taking the current highest bid.
    function takeHighestBid(address _nftContractAddress, uint256 _tokenId)
        external
        override
        onlyNftSeller(_nftContractAddress, _tokenId)
    {
        require(_isABidMade(_nftContractAddress, _tokenId), "cannot payout 0 bid");

        _transferNftToAuctionContract(_nftContractAddress, _tokenId);
        _transferNftAndPaySeller(_nftContractAddress, _tokenId);

        emit HighestBidTaken(_nftContractAddress, _tokenId);
    }

    //Query the owner of an NFT deposited for auction
    function ownerOfNFT(address _nftContractAddress, uint256 _tokenId)
        external
        override
        view
        returns (address)
    {
        address nftSeller = nftAuctions[_nftContractAddress][_tokenId].nftSeller;
        require(nftSeller != address(0), "NFT not deposited");

        return nftSeller;
    }

    //If the transfer of a bid has failed, allow the recipient to reclaim their amount later.
    function withdrawAllFailedCredits() external override {
        uint256 amount = failedTransferCredits[msg.sender];

        require(amount != 0, "no credits to withdraw");

        failedTransferCredits[msg.sender] = 0;

        (bool successfulWithdraw, ) = msg.sender.call{
            value: amount,
            gas: 20000
        }("");

        require(successfulWithdraw, "withdraw failed");
    }
}
