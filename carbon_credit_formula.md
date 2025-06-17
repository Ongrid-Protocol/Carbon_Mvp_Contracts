# OnGrid Protocol: Carbon Credit Generation Formula & Implementation Guide

## Executive Summary

This document outlines the methodology for generating carbon credits in the OnGrid Protocol based on grid emission factors, providing a simple yet scientifically sound approach to quantifying the carbon impact of solar energy generation across different countries.

## 1. Theoretical Foundation

### 1.1 Core Concept

Carbon credits in the OnGrid Protocol represent **avoided emissions** - the amount of CO2 that would have been emitted if the same amount of energy was generated from the local electrical grid instead of solar power.

### 1.2 Formula Overview

```
Carbon Credits (tonnes CO2e) = Energy Generated (MWh) × Grid Emission Factor (tonnes CO2e/MWh)
```

### 1.3 Unit Conversions

- **Input**: Energy data in kWh (from solar installations)
- **Grid Factors**: Stored as grams CO2e per kWh for precision
- **Output**: Carbon credits in tonnes CO2e (standard carbon market unit)
- **Token Representation**: Credits with 3 decimal precision (1.000 credit = 1000 smallest units)

## 2. Grid Emission Factors by Target Country

### 2.1 Country-Specific Data

Based on latest available data from IEA, national grid operators, and verified carbon standards:

| Country | Grid Emission Factor | Source Year | Grid Mix Composition |
|---------|---------------------|-------------|---------------------|
| Kenya | 512 g CO2e/kWh | 2022 | 70% hydro, 15% geothermal, 10% thermal, 5% other renewables |
| Nigeria | 894 g CO2e/kWh | 2022 | 80% natural gas, 15% hydro, 5% oil |
| South Africa | 928 g CO2e/kWh | 2022 | 85% coal, 10% nuclear, 5% renewables |
| Vietnam | 695 g CO2e/kWh | 2022 | 45% coal, 25% hydro, 20% gas, 10% renewables |
| Thailand | 574 g CO2e/kWh | 2022 | 50% natural gas, 25% coal, 15% hydro, 10% renewables |

### 2.2 Data Sources & Verification

- **Primary**: National electricity authorities and grid operators
- **Secondary**: IEA Energy Statistics, CDM methodologies
- **Verification**: Cross-referenced with Gold Standard and Verra databases
- **Update Frequency**: Annual review with quarterly monitoring

### 2.3 Regional Variations

For initial implementation, we use **national average factors**. Future versions will support:
- Sub-national grid regions (e.g., different states/provinces)
- Time-of-day emission factors (renewable vs. peak load periods)
- Marginal emission factors (what's displaced vs. average grid)

## 3. Mathematical Formula Implementation

### 3.1 Step-by-Step Calculation

```
Step 1: Convert kWh to MWh
Energy_MWh = Energy_kWh ÷ 1000

Step 2: Apply grid emission factor
Emissions_Avoided_tonnes = Energy_MWh × Grid_Factor_tonnes_per_MWh

Step 3: Convert to token units (3 decimals)
Credit_Tokens = Emissions_Avoided_tonnes × 1000
```

### 3.2 Example Calculation

**Scenario**: 500 kWh solar generation in Kenya

```
Energy_MWh = 500 ÷ 1000 = 0.5 MWh
Emissions_Avoided = 0.5 × 0.512 = 0.256 tonnes CO2e
Credit_Tokens = 0.256 × 1000 = 256 token units (0.256 credits)
```

### 3.3 Precision Considerations

- **Grid factors stored as**: `uint256` representing grams CO2e per kWh (scaled by 1e6)
  - Example: Kenya = 512,000,000 (represents 512 g/kWh)
- **Calculation precision**: Maintains 6 decimal places through computation
- **Final output**: Rounded to 3 decimal places for credit tokens

## 4. Smart Contract Architecture Refactoring

### 4.1 Current State Analysis

**Existing Structure**:
- Single global `emissionFactor` in `EnergyDataBridge`
- Applied uniformly to all energy data regardless of location
- Stored as `uint256` with 1e6 scaling

**Limitations**:
- No geographic differentiation
- Cannot handle country-specific factors
- No mechanism for factor updates
- Missing location data in energy submissions

### 4.2 Required Data Structure Changes

#### 4.2.1 Country Registry

```solidity
// New enum for supported countries
enum Country {
    KENYA,
    NIGERIA,
    SOUTH_AFRICA,
    VIETNAM,
    THAILAND
}

// Country-specific emission factors
mapping(Country => uint256) public countryEmissionFactors;

// Country metadata
struct CountryInfo {
    string name;
    string isoCode;
    uint256 emissionFactor; // grams CO2e per kWh, scaled by 1e6
    uint64 lastUpdated;
    bool isActive;
}
mapping(Country => CountryInfo) public countryRegistry;
```

#### 4.2.2 Enhanced Energy Data Structure

```solidity
struct EnergyData {
    bytes32 deviceId;
    address nodeOperatorAddress;
    uint256 energyKWh;
    uint64 timestamp;
    Country country; // NEW: Country enum
    bytes32 locationHash; // NEW: Optional precise location verification
}
```

#### 4.2.3 Location Verification

```solidity
// Device registration with location
struct RegisteredDevice {
    bytes32 deviceId;
    address owner;
    Country country;
    bytes32 locationProof; // Hash of coordinates + timestamp
    bool isVerified;
}
mapping(bytes32 => RegisteredDevice) public registeredDevices;
```

### 4.3 Contract Refactoring Plan

#### 4.3.1 EnergyDataBridge Changes

**New Functions Needed**:
1. `initializeCountryFactors()` - Set initial emission factors
2. `updateCountryEmissionFactor(Country, uint256)` - Admin function for updates
3. `registerDevice(bytes32, Country, bytes32)` - Device registration with location
4. `verifyDeviceLocation(bytes32)` - Location verification process
5. `getEmissionFactor(Country)` - Public getter for country factors

**Modified Functions**:
1. `submitEnergyDataBatch()` - Include country validation
2. `processBatch()` - Use country-specific factors in calculations
3. `_calculateCredits()` - New internal function with country parameter

#### 4.3.2 Access Control Extensions

**New Roles**:
- `COUNTRY_MANAGER_ROLE` - Can update emission factors
- `DEVICE_REGISTRAR_ROLE` - Can register and verify devices
- `LOCATION_VERIFIER_ROLE` - Can verify device locations

#### 4.3.3 Event Updates

**New Events**:
```solidity
event CountryEmissionFactorUpdated(Country indexed country, uint256 oldFactor, uint256 newFactor);
event DeviceRegistered(bytes32 indexed deviceId, Country indexed country, address indexed owner);
event DeviceLocationVerified(bytes32 indexed deviceId, bool verified);
```

### 4.4 Migration Strategy

#### 4.4.1 Backward Compatibility

1. **Maintain existing `emissionFactor`** as fallback for unspecified countries
2. **Gradual migration** - existing devices continue working
3. **Optional country specification** initially, then mandatory for new devices

#### 4.4.2 Deployment Sequence

1. **Phase 1**: Deploy updated contracts with country support
2. **Phase 2**: Initialize country emission factors
3. **Phase 3**: Begin device registration process
4. **Phase 4**: Enforce country specification for new submissions
5. **Phase 5**: Migrate existing devices (admin process)

## 5. Implementation Considerations

### 5.1 Data Quality & Verification

#### 5.1.1 Location Verification Methods

1. **GPS Coordinates**: Hashed with timestamp for privacy
2. **Government Registry**: Cross-reference with official databases
3. **Satellite Verification**: Future integration with satellite imagery
4. **Peer Verification**: Network consensus on device locations

#### 5.1.2 Factor Update Mechanisms

1. **Annual Reviews**: Scheduled updates based on grid changes
2. **Emergency Updates**: For significant grid composition changes
3. **Multi-signature Requirements**: Critical factor changes need multiple approvals
4. **Historical Tracking**: Maintain factor history for audit trails

### 5.2 Edge Cases & Error Handling

#### 5.2.1 Invalid Country Data

```solidity
// Validation checks needed
if (countryEmissionFactors[country] == 0) {
    // Fall back to global factor or revert
}
```

#### 5.2.2 Device Location Disputes

- Challenge mechanism for disputed locations
- Appeal process through governance
- Temporary suspension pending resolution

#### 5.2.3 Cross-Border Installations

- Devices near borders may need special handling
- Consider local grid connections vs. administrative boundaries

### 5.3 Gas Optimization

#### 5.3.1 Batch Processing

- Process multiple countries in single transaction
- Cache frequently accessed factors
- Optimize storage layout for gas efficiency

#### 5.3.2 Data Compression

- Use enums instead of strings for countries
- Pack location data efficiently
- Minimize storage writes for factor updates

## 6. Testing & Validation Framework

### 6.1 Unit Tests Required

1. **Country factor calculations** - Test all supported countries
2. **Edge case handling** - Invalid countries, zero factors
3. **Precision maintenance** - Verify no rounding errors
4. **Access control** - Role-based function restrictions

### 6.2 Integration Tests

1. **End-to-end flow** - Device registration through credit generation
2. **Multi-country batches** - Mixed country data processing
3. **Factor updates** - Live update scenarios
4. **Migration testing** - Backward compatibility verification

### 6.3 Real-World Validation

1. **Spot checks** - Compare calculated credits with external standards
2. **Grid data verification** - Cross-reference with national statistics
3. **Carbon market alignment** - Ensure credits meet market standards

## 7. Governance & Maintenance

### 7.1 Factor Update Governance

#### 7.1.1 Update Triggers

- Annual mandatory review
- >5% change in national grid composition
- New renewable energy capacity >10% of total
- Policy changes affecting emission factors

#### 7.1.2 Approval Process

1. **Technical Review**: Verify data sources and calculations
2. **Community Comment**: 7-day public review period
3. **Multi-sig Approval**: Requires 3/5 governance signatures
4. **Implementation**: 24-hour timelock before activation

### 7.2 Expansion Planning

#### 7.2.1 New Country Addition

1. **Market Research**: Assess demand and regulatory environment
2. **Data Collection**: Establish reliable emission factor sources
3. **Technical Integration**: Add country enum and factor
4. **Partner Network**: Establish local verification capabilities

#### 7.2.2 Advanced Features Roadmap

- **Sub-national factors**: State/province level granularity
- **Time-based factors**: Hourly/seasonal variations
- **Marginal factors**: What generation actually displaces
- **Forward-looking**: Projected future grid compositions

## 8. Conclusion

This methodology provides a robust foundation for carbon credit generation while maintaining simplicity and scientific accuracy. The country-specific approach ensures credits reflect real environmental impact while supporting OnGrid's expansion across diverse energy markets.

The implementation prioritizes:
- **Scientific Rigor**: Verified emission factors from authoritative sources
- **Operational Simplicity**: Clear calculations with minimal complexity
- **Scalability**: Architecture supports future enhancements
- **Transparency**: All factors and calculations publicly verifiable
- **Flexibility**: Can adapt to changing grid compositions and market needs

This approach positions OnGrid Protocol as a credible carbon credit generator while building the technical foundation for sophisticated future enhancements.