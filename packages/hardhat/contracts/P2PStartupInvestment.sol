// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.9.0;

contract P2PStartupInvestment {
    // The minimum and maximum amount of ETH that can be invested
    uint public constant MIN_INVESTMENT_AMOUNT = 0.1 ether;
    uint public constant MAX_INVESTMENT_AMOUNT = 10 ether;
    // The minimum and maximum equity percentage that can be offered for an investment
    uint public constant MIN_EQUITY_PERCENTAGE = 1;
    uint public constant MAX_EQUITY_PERCENTAGE = 10;

    struct Investment {
        uint amount;
        uint equityPercentage;
        uint fundingDeadline;
        string startupName;
        string description;
        uint valuation;
        address payable investor;
        address payable startup;
        bool active;
        bool repaid;
    }

    mapping(uint => Investment) public investments;
    uint public investmentCount;

    event InvestmentCreated(
        uint investmentId,
        uint amount,
        uint equityPercentage,
        uint fundingDeadline,
        string startupName,
        string description,
        uint valuation,
        address investor,
        address startup
    );

    event InvestmentFunded(uint investmentId, address funder, uint amount);
    event InvestmentRepaid(uint investmentId, uint amount);

    modifier onlyActiveInvestment(uint _investmentId) {
        require(investments[_investmentId].active, "Investment is not active");
        _;
    }

    modifier onlyInvestor(uint _investmentId) {
        require(
            msg.sender == investments[_investmentId].investor,
            "Only the investor can perform this action"
        );
        _;
    }

    function createInvestment(
        uint _amount,
        uint _equityPercentage,
        string memory _startupName,
        string memory _description,
        uint _valuation
    ) external payable {
        require(
            _amount >= MIN_INVESTMENT_AMOUNT &&
                _amount <= MAX_INVESTMENT_AMOUNT,
            "Investment amount must be between MIN_INVESTMENT_AMOUNT and MAX_INVESTMENT_AMOUNT"
        );
        require(
            _equityPercentage >= MIN_EQUITY_PERCENTAGE &&
                _equityPercentage <= MAX_EQUITY_PERCENTAGE,
            "Equity percentage must be between MIN_EQUITY_PERCENTAGE and MAX_EQUITY_PERCENTAGE"
        );
        require(bytes(_startupName).length > 0, "Startup name cannot be empty");
        require(bytes(_description).length > 0, "Description cannot be empty");
        require(_valuation > 0, "Startup valuation must be greater than 0");

        uint _fundingDeadline = block.timestamp + (1 days);
        uint investmentId = investmentCount++;

        Investment storage investment = investments[investmentId];
        investment.amount = _amount;
        investment.equityPercentage = _equityPercentage;
        investment.fundingDeadline = _fundingDeadline;
        investment.startupName = _startupName;
        investment.description = _description;
        investment.valuation = _valuation;
        investment.investor = payable(msg.sender);
        investment.startup = payable(address(0));
        investment.active = true;
        investment.repaid = false;

        emit InvestmentCreated(
            investmentId,
            _amount,
            _equityPercentage,
            _fundingDeadline,
            _startupName,
            _description,
            _valuation,
            msg.sender,
            address(0)
        );
    }

    function fundInvestment(
        uint _investmentId
    ) external payable onlyActiveInvestment(_investmentId) {
        Investment storage investment = investments[_investmentId];
        require(
            msg.sender != investment.investor,
            "Investor cannot fund their own investment"
        );
        require(investment.amount == msg.value, "Incorrect investment amount");
        require(
            block.timestamp <= investment.fundingDeadline,
            "Investment funding deadline has passed"
        );
        payable(address(this)).transfer(msg.value);
        investment.startup = payable(msg.sender);
        investment.active = false;

        emit InvestmentFunded(_investmentId, msg.sender, msg.value);
    }

    function repayInvestment(
        uint _investmentId
    )
        external
        payable
        onlyActiveInvestment(_investmentId)
        onlyInvestor(_investmentId)
    {
        Investment storage investment = investments[_investmentId];
        require(msg.value == investment.amount, "Incorrect repayment amount");
        investment.startup.transfer(msg.value);
        investment.repaid = true;
        investment.active = false;

        emit InvestmentRepaid(_investmentId, msg.value);
    }

    function getInvestmentInfo(
        uint _investmentId
    )
        external
        view
        returns (
            uint amount,
            uint equityPercentage,
            uint fundingDeadline,
            string memory startupName,
            string memory description,
            uint valuation,
            address investor,
            address startup,
            bool active,
            bool repaid
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
            investment.repaid
        );
    }

    function withdrawFunds(
        uint _investmentId
    ) external onlyInvestor(_investmentId) {
        Investment storage investment = investments[_investmentId];
        require(!investment.active);
        payable(msg.sender).transfer(investment.amount);
    }
}
