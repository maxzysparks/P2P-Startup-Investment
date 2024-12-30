// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract P2PStartupInvestment is ReentrancyGuard, Pausable, Ownable {
    // Constants
    uint256 public constant MIN_INVESTMENT_AMOUNT = 0.1 ether;
    uint256 public constant MAX_INVESTMENT_AMOUNT = 10 ether;
    uint256 public constant MIN_EQUITY_PERCENTAGE = 1;
    uint256 public constant MAX_EQUITY_PERCENTAGE = 10;
    uint256 public constant MAX_DESCRIPTION_LENGTH = 1000;
    uint256 public constant MAX_NAME_LENGTH = 50;
    uint256 public constant PERCENTAGE_BASE = 100;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant FEE_UPDATE_DELAY = 1 days;
    uint256 public constant MIN_LOCK_PERIOD = 1 days;
    uint256 public constant MIN_PLATFORM_FEE = 0.001 ether;
    uint256 public constant MAX_INVESTMENTS = 1000;

    struct Investment {
        uint256 amount;
        uint256 equityPercentage;
        uint256 fundingDeadline;
        bytes32 startupName;
        bytes description;
        uint256 valuation;
        address payable investor;
        address payable startup;
        bool active;
        bool repaid;
        bool funded;
        bool withdrawn;
    }

    // State variables
    mapping(uint256 => Investment) public investments;
    mapping(uint256 => uint256) public lastFeeUpdate;
    uint256 public investmentCount;
    uint256 public platformFeePercentage = 1; // 1% platform fee
    uint256 public fundingDurationInDays = 1; // Configurable funding duration

    // Events
    event InvestmentCreated(
        uint256 indexed investmentId,
        uint256 indexed amount,
        uint256 equityPercentage,
        uint256 fundingDeadline,
        bytes32 indexed startupName,
        bytes description,
        uint256 valuation,
        address investor,
        address startup
    );
    event InvestmentFunded(
        uint256 indexed investmentId, 
        address indexed funder, 
        uint256 indexed amount
    );
    event InvestmentRepaid(
        uint256 indexed investmentId, 
        uint256 indexed amount, 
        address indexed investor
    );
    event FundsWithdrawn(
        uint256 indexed investmentId, 
        uint256 indexed amount, 
        address indexed investor
    );
    event InvestmentCancelled(
        uint256 indexed investmentId, 
        uint256 amount, 
        address indexed investor
    );
    event PlatformFeeUpdated(uint256 indexed newFeePercentage);
    event FundingDurationUpdated(uint256 indexed newDuration);
    event EmergencyWithdrawal(uint256 amount, address indexed owner);

    // Modifiers
    modifier onlyActiveInvestment(uint256 _investmentId) {
        require(investments[_investmentId].active, "Investment is not active");
        _;
    }

    modifier onlyInvestor(uint256 _investmentId) {
        require(
            msg.sender == investments[_investmentId].investor,
            "Only the investor can perform this action"
        );
        _;
    }

    modifier onlyStartup(uint256 _investmentId) {
        require(
            msg.sender == investments[_investmentId].startup,
            "Only the startup can perform this action"
        );
        _;
    }

    modifier validInvestmentId(uint256 _investmentId) {
        require(_investmentId < investmentCount, "Invalid investment ID");
        _;
    }

    // Constructor
    constructor() {
        require(msg.sender != address(0), "Invalid owner address");
        _transferOwnership(msg.sender);
    }

    // External functions
    function createInvestment(
        uint256 _amount,
        uint256 _equityPercentage,
        string memory _startupName,
        string memory _description,
        uint256 _valuation
    ) external payable whenNotPaused nonReentrant {
        require(investmentCount < MAX_INVESTMENTS, "Max investments reached");
        require(_amount > 0, "Amount must be greater than 0");
        require(msg.value == _amount, "Sent value does not match investment amount");
        require(
            _amount >= MIN_INVESTMENT_AMOUNT && _amount <= MAX_INVESTMENT_AMOUNT,
            "Invalid investment amount"
        );
        require(
            _equityPercentage >= MIN_EQUITY_PERCENTAGE &&
                _equityPercentage <= MAX_EQUITY_PERCENTAGE,
            "Invalid equity percentage"
        );
        require(bytes(_startupName).length > 0 && bytes(_startupName).length <= MAX_NAME_LENGTH, "Invalid startup name length");
        require(bytes(_startupName).length <= 32, "Startup name too long for bytes32");
        require(bytes(_description).length > 0 && bytes(_description).length <= MAX_DESCRIPTION_LENGTH, "Invalid description length");
        require(_valuation > 0, "Invalid startup valuation");

        uint256 _fundingDeadline = block.timestamp + (fundingDurationInDays * 1 days);
        require(_fundingDeadline > block.timestamp, "Invalid funding deadline");

        uint256 investmentId = investmentCount++;

        Investment storage investment = investments[investmentId];
        investment.amount = _amount;
        investment.equityPercentage = _equityPercentage;
        investment.fundingDeadline = _fundingDeadline;
        investment.startupName = bytes32(bytes(_startupName));
        investment.description = bytes(_description);
        investment.valuation = _valuation;
        investment.investor = payable(msg.sender);
        investment.active = true;

        emit InvestmentCreated(
            investmentId,
            _amount,
            _equityPercentage,
            _fundingDeadline,
            investment.startupName,
            investment.description,
            _valuation,
            msg.sender,
            address(0)
        );
    }

    function fundInvestment(
        uint256 _investmentId
    ) external payable whenNotPaused nonReentrant onlyActiveInvestment(_investmentId) validInvestmentId(_investmentId) {
        Investment storage investment = investments[_investmentId];
        
        require(!investment.funded, "Investment already funded");
        require(msg.sender != address(0), "Invalid sender address");
        require(
            msg.sender != investment.investor,
            "Investor cannot fund their own investment"
        );
        require(investment.amount == msg.value, "Incorrect investment amount");
        require(
            block.timestamp <= investment.fundingDeadline,
            "Investment funding deadline has passed"
        );

        investment.startup = payable(msg.sender);
        investment.funded = true;
        investment.active = false;

        emit InvestmentFunded(_investmentId, msg.sender, msg.value);
    }

    function repayInvestment(
        uint256 _investmentId
    ) external payable whenNotPaused nonReentrant validInvestmentId(_investmentId) onlyStartup(_investmentId) {
        Investment storage investment = investments[_investmentId];
        
        require(investment.funded, "Investment not funded");
        require(!investment.repaid, "Investment already repaid");
        require(!investment.withdrawn, "Investment already withdrawn");
        require(msg.value == investment.amount, "Incorrect repayment amount");

        investment.repaid = true;
        
        uint256 platformFee = (msg.value * platformFeePercentage * PRECISION) / (PERCENTAGE_BASE * PRECISION);
        platformFee = platformFee < MIN_PLATFORM_FEE ? MIN_PLATFORM_FEE : platformFee;
        uint256 investorAmount = msg.value - platformFee;
        
        (bool successInvestor, ) = investment.investor.call{value: investorAmount}("");
        require(successInvestor, "Transfer to investor failed");
        
        (bool successOwner, ) = owner().call{value: platformFee}("");
        require(successOwner, "Transfer of platform fee failed");

        emit InvestmentRepaid(_investmentId, msg.value, investment.investor);
    }

    function withdrawInvestment(
        uint256 _investmentId
    ) external nonReentrant validInvestmentId(_investmentId) onlyInvestor(_investmentId) {
        Investment storage investment = investments[_investmentId];
        
        require(investment.funded, "Investment not funded");
        require(!investment.withdrawn, "Funds already withdrawn");
        require(!investment.repaid, "Investment already repaid");
        require(
            block.timestamp >= investment.fundingDeadline + MIN_LOCK_PERIOD,
            "Lock period not ended"
        );
        
        uint256 amount = investment.amount;
        investment.withdrawn = true;
        
        (bool success, ) = investment.investor.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit FundsWithdrawn(_investmentId, amount, investment.investor);
    }

    function cancelInvestment(
        uint256 _investmentId
    ) external nonReentrant validInvestmentId(_investmentId) onlyInvestor(_investmentId) {
        Investment storage investment = investments[_investmentId];
        
        require(investment.active, "Investment not active");
        require(!investment.funded, "Investment already funded");
        require(
            block.timestamp > investment.fundingDeadline,
            "Funding deadline not passed"
        );

        investment.active = false;
        
        if(address(this).balance >= investment.amount) {
            (bool success, ) = investment.investor.call{value: investment.amount}("");
            require(success, "Fund return failed");
        }
        
        emit InvestmentCancelled(_investmentId, investment.amount, investment.investor);
    }

    // Admin functions
    function updatePlatformFee(uint256 _newFeePercentage) external onlyOwner {
        require(block.timestamp >= lastFeeUpdate[_newFeePercentage] + FEE_UPDATE_DELAY, "Fee update too soon");
        require(_newFeePercentage <= 5, "Fee too high");
        lastFeeUpdate[_newFeePercentage] = block.timestamp;
        platformFeePercentage = _newFeePercentage;
        emit PlatformFeeUpdated(_newFeePercentage);
    }

    function updateFundingDuration(uint256 _newDurationInDays) external onlyOwner {
        require(_newDurationInDays > 0, "Invalid duration");
        fundingDurationInDays = _newDurationInDays;
        emit FundingDurationUpdated(_newDurationInDays);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // View functions
    function getInvestmentInfo(
        uint256 _investmentId
    )
        external
        view
        validInvestmentId(_investmentId)
        returns (
            uint256 amount,
            uint256 equityPercentage,
            uint256 fundingDeadline,
            bytes32 startupName,
            bytes memory description,
            uint256 valuation,
            address investor,
            address startup,
            bool active,
            bool repaid,
            bool funded,
            bool withdrawn
        )
    {
        Investment storage investment = investments[_investmentId];
        return (
            investment.amount,
            investment.equityPercentage,
            investment.fundingDeadline,
            investment.startupName,
            investment.description,
            investment.valuation,
            investment.investor,
            investment.startup,
            investment.active,
            investment.repaid,
            investment.funded,
            investment.withdrawn
        );
    }

    function getContractBalance() external view onlyOwner returns (uint256) {
        return address(this).balance;
    }

    // Emergency function
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        (bool success, ) = owner().call{value: balance}("");
        require(success, "Emergency withdrawal failed");
        emit EmergencyWithdrawal(balance, owner());
    }
}