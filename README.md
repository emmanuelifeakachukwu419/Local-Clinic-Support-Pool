# 🏥 Local Clinic Support Pool

A decentralized autonomous organization (DAO) smart contract for community-funded healthcare initiatives. This contract enables transparent funding distribution to local clinics based on performance metrics and community governance.

## 🎯 Problem & Solution

**Problem**: Small clinics often lack funding and oversight for effective patient care.

**Solution**: 
- 💰 Community members donate to a pooled smart contract fund
- 📊 Funds are disbursed automatically to clinics that meet predefined performance KPIs
- 🗳️ DAO voting system for clinic inclusion and removal decisions
- 🔍 Transparent tracking of all donations and disbursements

## ✨ Features

### 🏦 Core Functionality
- **Community Donations**: Anyone can contribute STX tokens to the pool
- **Clinic Registration**: Healthcare providers can register and request funding
- **Performance Tracking**: Oracle-based performance score updates
- **Automated Disbursement**: Funds distributed based on performance metrics
- **DAO Governance**: Community voting on clinic approval/removal

### 🔐 Security Features
- **Owner Controls**: Emergency withdrawal and oracle management
- **Minimum Thresholds**: Performance requirements for funding eligibility
- **Voting Periods**: Time-limited voting sessions with clear deadlines
- **Access Controls**: Role-based permissions for different operations

## 🚀 Getting Started

### Prerequisites
- [Clarinet](https://docs.hiro.so/stacks/clarinet) installed
- Basic understanding of Stacks blockchain and Clarity

### Installation
```bash
git clone <repository-url>
cd Local-Clinic-Support-Pool
clarinet check
```

### Running Tests
```bash
npm install
npm test
```

## 📖 Usage Guide

### 💝 Making a Donation
```clarity
(contract-call? .Local-Clinic-Support-Pool donate u5000000) ;; Donate 5 STX
```

### 🏥 Registering a Clinic  
```clarity
(contract-call? .Local-Clinic-Support-Pool register-clinic "Community Health Center")
```

### 🗳️ Voting on Clinic Approval
```clarity
(contract-call? .Local-Clinic-Support-Pool vote-on-clinic u1 true) ;; Vote yes for clinic ID 1
```

### 📊 Updating Performance (Oracle Only)
```clarity
(contract-call? .Local-Clinic-Support-Pool update-clinic-performance u1 u85) ;; 85% score
```

### 💸 Disbursing Funds
```clarity
(contract-call? .Local-Clinic-Support-Pool disburse-funds u1) ;; Disburse to clinic ID 1
```

## 🔧 Contract Functions

### Public Functions

| Function | Description | Parameters |
|----------|-------------|------------|
| `donate` | Add funds to the pool | `amount: uint` |
| `register-clinic` | Register a new clinic | `name: string-ascii` |
| `vote-on-clinic` | Vote on clinic approval/removal | `clinic-id: uint, vote: bool` |
| `finalize-voting` | Close voting and apply results | `clinic-id: uint` |
| `update-clinic-performance` | Update performance score (oracle) | `clinic-id: uint, score: uint` |
| `disburse-funds` | Distribute funds to eligible clinic | `clinic-id: uint` |
| `remove-clinic` | Initiate clinic removal vote (owner) | `clinic-id: uint` |
| `set-oracle` | Update oracle address (owner) | `new-oracle: principal` |
| `emergency-withdraw` | Emergency fund withdrawal (owner) | `amount: uint` |

### Read-Only Functions

| Function | Description | Returns |
|----------|-------------|---------|
| `get-clinic-details` | Get clinic information | Clinic data or none |
| `get-voting-session` | Get voting session info | Voting session data |
| `get-pool-balance` | Current pool balance | `uint` |
| `get-donor-stats` | Donor contribution history | Donor data or none |
| `calculate-disbursement` | Calculate potential disbursement | `uint` or none |

## 📊 Key Constants

- **MIN_DONATION**: 1 STX (1,000,000 microSTX)
- **MIN_PERFORMANCE_SCORE**: 70% required for funding
- **VOTING_PERIOD**: 144 blocks (~24 hours)
- **DISBURSEMENT_INTERVAL**: 1008 blocks (~1 week)

## 🔄 Workflow

1. **📋 Clinic Registration**: Healthcare providers register with the contract
2. **🗳️ Community Voting**: DAO members vote on clinic approval (24-hour period)
3. **✅ Approval Process**: Clinics with majority approval become "active"
4. **💰 Community Funding**: Users donate STX tokens to the shared pool
5. **📈 Performance Updates**: Oracle updates clinic performance scores
6. **💸 Automatic Disbursement**: Eligible clinics (≥70% score) receive proportional funding
7. **🔄 Continuous Monitoring**: Ongoing performance tracking and community governance

## 🚨 Error Codes

| Code | Error | Description |
|------|-------|-------------|
| u100 | ERR_NOT_OWNER | Only contract owner can perform this action |
| u101 | ERR_CLINIC_NOT_FOUND | Clinic ID does not exist |
| u102 | ERR_CLINIC_ALREADY_EXISTS | Clinic already registered |
| u103 | ERR_INSUFFICIENT_FUNDS | Not enough funds in pool |
| u104 | ERR_INVALID_AMOUNT | Amount below minimum threshold |
| u105 | ERR_CLINIC_NOT_ACTIVE | Clinic not in active status |
| u106 | ERR_ALREADY_VOTED | User already voted in this session |
| u107 | ERR_VOTING_ENDED | Voting period has expired |
| u108 | ERR_NOT_ORACLE | Only oracle can update performance |
| u109 | ERR_INVALID_PERFORMANCE | Invalid performance score (>100) |

## 🌟 Impact

This smart contract enables:
- **🏥 Quality Healthcare**: Incentivizes clinics to maintain high performance standards
- **🤝 Community Ownership**: Democratic governance over funding decisions  
- **💎 Transparent Funding**: All transactions recorded on blockchain
- **📈 Continuous Improvement**: Performance-based funding drives better outcomes
- **🔒 Trust & Accountability**: Automated, tamper-proof fund distribution

## 🛡️ Security Considerations

- Oracle address should be set to a trusted performance monitoring service
- Emergency withdrawal is available for contract owner in critical situations
- All user inputs are validated against defined constraints
- Voting periods prevent rushed decisions and allow community participation

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly with `clarinet test`
5. Submit a pull request

## 📜 License

This project is open source and available under the MIT License.

---

*Built with ❤️ for better healthcare accessibility and community empowerment*
