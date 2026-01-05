# Rule Format Guide

Kemal WAF supports YAML-based rule definitions with multiple operators and transformations.

## Simple Format (Backward Compatible)

```yaml
---
id: 942100
msg: "SQL Injection Attack Detected"
variables:
  - ARGS
  - BODY
  - REQUEST_LINE
pattern: "(?i)(union.*select|select.*from|insert.*into)"
action: deny
transforms:
  - url_decode
  - lowercase
```

## Advanced Format (OWASP CRS)

```yaml
---
id: 942100
name: "SQL Injection - LibInjection Detection"
msg: "SQL Injection Attack Detected via libinjection"
category: "sqli"
severity: "CRITICAL"
paranoia_level: 1
operator: "libinjection_sqli"  # or "regex", "libinjection_xss", "contains", "starts_with"
pattern: null  # null for LibInjection, pattern for regex
variables:
  - type: COOKIE
  - type: ARGS
  - type: ARGS_NAMES
  - type: HEADERS
    names: ["User-Agent", "Referer"]  # Filter for specific headers
  - type: BODY
transforms:
  - none
  - utf8_to_unicode
  - url_decode_uni
  - remove_nulls
action: "deny"
tags:
  - "OWASP_CRS"
  - "attack-sqli"
  - "paranoia-level/1"
```

## Rule Fields

### Required Fields

- **id**: Unique rule identifier (integer, required)
- **msg**: Rule description (string, required)
- **variables**: List of variables to check (array, required)
- **action**: `deny` (block) or `log` (log only) (string, required)

### Optional Fields

- **name**: Rule name (string, optional)
- **category**: Rule category: `sqli`, `xss`, `lfi`, `rce`, etc. (string, optional)
- **severity**: Severity level: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW` (string, optional)
- **paranoia_level**: Paranoia level (integer, optional, default: 1)
- **operator**: Matching operator (string, optional, default: "regex")
- **pattern**: Regex pattern or string pattern (string?, optional - null for LibInjection)
- **transforms**: Optional transformation list (array, optional)
- **tags**: Rule tags (array, optional)

## Operators

### regex (Default)
Standard regex pattern matching.

```yaml
operator: "regex"
pattern: "(?i)(union.*select|select.*from)"
```

### libinjection_sqli
LibInjection SQL injection detection (no pattern needed).

```yaml
operator: "libinjection_sqli"
pattern: null
```

### libinjection_xss
LibInjection XSS detection (no pattern needed).

```yaml
operator: "libinjection_xss"
pattern: null
```

### contains
Simple string contains check.

```yaml
operator: "contains"
pattern: "<script>"
```

### starts_with
String starts with check.

```yaml
operator: "starts_with"
pattern: "javascript:"
```

## Variables

### Simple Format
```yaml
variables:
  - ARGS
  - BODY
  - REQUEST_LINE
```

### Advanced Format
```yaml
variables:
  - type: HEADERS
    names: ["User-Agent", "Referer"]  # Only check these headers
  - type: ARGS
  - type: BODY
```

### Supported Variables

- **REQUEST_LINE**: HTTP request line (METHOD PATH PROTOCOL)
- **REQUEST_FILENAME**: Request path
- **REQUEST_BASENAME**: Basename of path
- **ARGS**: Query string parameters (in key=value format)
- **ARGS_NAMES**: Parameter names only
- **HEADERS**: HTTP headers (in Header-Name: value format)
- **BODY**: Request body
- **COOKIE**: Cookie header
- **COOKIE_NAMES**: Cookie names only

## Transformations

Transformations are applied in order before pattern matching:

- **none**: No transform
- **url_decode**: Apply URL decode
- **url_decode_uni**: Unicode-aware URL decode
- **lowercase**: Convert to lowercase
- **utf8_to_unicode**: UTF-8 to Unicode conversion
- **remove_nulls**: Remove null bytes
- **replace_comments**: Remove SQL/HTML comments

### Example with Multiple Transforms

```yaml
transforms:
  - url_decode      # %27 -> '
  - url_decode_uni  # %u0027 -> '
  - lowercase       # SELECT -> select
  - remove_nulls    # Remove \0 bytes
```

## Actions

- **deny**: Block the request (returns 403 Forbidden)
- **log**: Log the match but allow the request (useful for testing)

## Adding New Rules

### Manual YAML Creation

1. Create a new `.yaml` file in the `rules/` directory (or subdirectories)
2. Define the rule using the format above
3. WAF will automatically load the new rule within 5 seconds (recursive directory scanning)

### Example: SQL Injection Rule

Create `rules/custom/sqli-detection.yaml`:

```yaml
---
id: 942100
name: "SQL Injection - LibInjection Detection"
msg: "SQL Injection Attack Detected via libinjection"
category: "sqli"
severity: "CRITICAL"
operator: "libinjection_sqli"
pattern: null
variables:
  - type: ARGS
  - type: ARGS_NAMES
  - type: BODY
  - type: COOKIE
transforms:
  - none
  - url_decode_uni
  - remove_nulls
action: "deny"
tags:
  - "OWASP_CRS"
  - "attack-sqli"
```

### Example: XSS Rule

Create `rules/custom/xss-detection.yaml`:

```yaml
---
id: 941100
name: "XSS Attack Detection"
msg: "XSS Attack Detected"
category: "xss"
severity: "HIGH"
operator: "libinjection_xss"
pattern: null
variables:
  - type: ARGS
  - type: BODY
  - type: HEADERS
    names: ["User-Agent", "Referer"]
transforms:
  - url_decode_uni
  - lowercase
action: "deny"
tags:
  - "OWASP_CRS"
  - "attack-xss"
```

### Example: Custom Regex Rule

Create `rules/custom/path-traversal.yaml`:

```yaml
---
id: 930100
name: "Path Traversal Attack"
msg: "Path Traversal Attack Detected"
category: "lfi"
severity: "HIGH"
operator: "regex"
pattern: "(?i)(\.\./|\.\.\\\|%2e%2e%2f|%2e%2e%5c)"
variables:
  - type: REQUEST_FILENAME
  - type: ARGS
transforms:
  - url_decode
  - url_decode_uni
action: "deny"
tags:
  - "attack-lfi"
```

## OWASP CRS Rules

The project includes OWASP CRS SQL Injection rules (in the `rules/owasp-crs/` folder):

- **942100**: LibInjection SQLi Detection
- **942140**: Common DB Names Detection
- **942151**: SQL Function Names Detection
- **942160**: Sleep/Benchmark Detection
- **942170**: Benchmark and Sleep Injection

These rules have been manually converted from OWASP CRS to YAML format. To add new rules:

1. Reference the OWASP CRS documentation
2. Copy regex patterns from OWASP CRS
3. Map transforms correctly
4. Create a rule file in YAML format

## LibInjection Installation

The LibInjection C library must be installed on the system or built from source:

```bash
# To build LibInjection from source
git clone https://github.com/libinjection/libinjection.git
cd libinjection
make
sudo make install
```

It is linked during Crystal build with the `-linjection` flag.

## Rule Testing

### Test in Observe Mode

Before deploying rules, test them in observe mode:

```yaml
# config/waf.yml
waf:
  mode: observe  # Logs but doesn't block
```

### Test Requests

```bash
# SQL Injection test
curl "http://localhost:3030/api/users?id=1' OR '1'='1"

# XSS test
curl "http://localhost:3030/search?q=<script>alert('xss')</script>"

# Check logs
docker logs kemal-waf | grep "OBSERVE MODE"
```

## Best Practices

1. **Start with observe mode** to test rules before blocking
2. **Use LibInjection** for SQLi/XSS detection (more accurate than regex)
3. **Apply appropriate transforms** (url_decode, lowercase, etc.)
4. **Test rules thoroughly** before deploying to production
5. **Use meaningful rule IDs** (follow OWASP CRS numbering if possible)
6. **Add tags** for better organization and filtering
7. **Document custom rules** with clear messages

## Rule Organization

Organize rules in subdirectories:

```
rules/
  basic-rules.yaml
  sqli-rules.yaml
  xss-rules.yaml
  custom/
    domain-specific.yaml
  owasp-crs/
    sqli-rules.yaml
```

Rules in subdirectories are automatically loaded.

