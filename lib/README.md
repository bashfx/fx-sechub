# Security Library (lib/)

Organized security tools and utilities for the superhard security toolkit.

## Structure

### `detect/` - Detection & Discovery Tools
Tools that identify threats, vulnerabilities, and system components without taking action.

- **Purpose**: Find, enumerate, and identify security concerns
- **Usage**: Non-invasive discovery and threat detection
- **Output**: Reports, logs, evidence for further analysis

### `analyze/` - Analysis & Investigation Tools  
Tools that examine, monitor, and analyze security data and system behavior.

- **Purpose**: Deep analysis of identified threats and system behavior
- **Usage**: Forensic analysis, monitoring, and intelligence gathering
- **Output**: Analysis reports, intelligence briefings, monitoring data

### `defend/` - Defensive Action Tools
Tools that actively block, disable, or remediate security threats.

- **Purpose**: Active security measures and threat mitigation
- **Usage**: Blocking attacks, disabling threats, hardening systems
- **Output**: System changes, defensive configurations

### `test/` - Testing & Validation Tools
Tools that test system functionality, API connectivity, and security measures.

- **Purpose**: Validate functionality and test security implementations
- **Usage**: API testing, functionality verification, security validation
- **Output**: Test results, connectivity reports, validation status

### `common/` - Shared & Generic Tools
Tools that provide general-purpose security functionality across multiple use cases.

- **Purpose**: Generic security auditing, shared utilities, foundation tools
- **Usage**: General system hardening assessment, baseline security checks
- **Output**: System security reports, hardening recommendations, compliance checks

### `experiment/` - One-off & Experimental Tools
Tools that are experimental, proof-of-concept, or single-use investigative scripts.

- **Purpose**: Research, experimentation, and ad-hoc security investigations
- **Usage**: Custom analysis, prototype tools, investigation-specific scripts
- **Output**: Research data, experimental results, custom intelligence

### `support/` - System Cache & Evidence Management
Tools that manage AI system cache files, logs, and evidence preservation.

- **Purpose**: Cache cleanup, evidence preservation, forensic data packaging
- **Usage**: System maintenance, forensic analysis preparation, evidence archival
- **Output**: Packaged evidence archives, cleaned cache directories, preserved logs

## Tool Invocation

Tools in lib/ are organized by function and can be invoked directly or through dispatchers:

```bash
# Direct invocation
lib/detect/detect_ollama.sh
lib/analyze/claude_context_monitor.sh  
lib/defend/block_telemetry.sh
lib/test/test_claude.sh

# Future dispatcher pattern
lib/dispatch.sh detect ollama
lib/dispatch.sh analyze claude-context
lib/dispatch.sh defend block-telemetry
lib/dispatch.sh test claude
```

## Integration with Security Pantheon

- **Snoopy** uses all categories for comprehensive forensic investigation
- **Miragio** primarily uses detect/defend for telemetry protection
- **Bouncer** uses detect/analyze for resource monitoring  
- **Fingers** uses analyze/defend for MCP protocol security