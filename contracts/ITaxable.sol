// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface ITaxable {
    function setTaxTiersTwap(uint8 _index, uint256 _value)
        external
        returns (bool);

    function setTaxTiersRate(uint8 _index, uint256 _value)
        external
        returns (bool);

    function enableAutoCalculateTax() external returns (bool);

    function disableAutoCalculateTax() external returns (bool);

    function taxRate() external view returns (uint256);

    function setTaxCollectorAddress(address _taxCollectorAddress)
        external
        returns (bool);

    function setTaxRate(uint256 _taxRate) external returns (bool);

    function setBurnThreshold(uint256 _burnThreshold) external returns (bool);

    function excludeAddress(address _address) external returns (bool);

    function isAddressExcluded(address _address) external returns (bool);

    function includeAddress(address _address) external returns (bool);

    function setSvnOracle(address _hamsterOracle) external returns (bool);

    function setTaxOffice(address _taxOffice) external returns (bool);
}
