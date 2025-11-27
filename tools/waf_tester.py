#!/usr/bin/env python3
"""
WAF Test Suite - kemal-korur
Çeşitli saldırı payload'larını test eder ve detaylı rapor üretir
"""

import requests
import json
import sys
import time
from datetime import datetime
from typing import Dict, List, Tuple
from dataclasses import dataclass
from colorama import init, Fore, Style, Back

# Colorama'yı başlat
init(autoreset=True)

@dataclass
class TestResult:
    name: str
    category: str
    payload: str
    expected_blocked: bool
    actual_blocked: bool
    status_code: int
    response_time: float
    rule_id: int = None
    message: str = None
    error: str = None

class WAFTester:
    def __init__(self, base_url: str = "http://localhost:3000", timeout: int = 5):
        self.base_url = base_url.rstrip('/')
        self.timeout = timeout
        self.results: List[TestResult] = []
        self.session = requests.Session()
        
    def test_request(self, method: str, path: str, params: Dict = None, 
                    data: Dict = None, headers: Dict = None) -> Tuple[int, Dict, float]:
        """Tek bir istek gönder ve sonucu döndür"""
        url = f"{self.base_url}{path}"
        start_time = time.time()
        
        try:
            if method.upper() == "GET":
                response = self.session.get(url, params=params, headers=headers, timeout=self.timeout)
            elif method.upper() == "POST":
                response = self.session.post(url, json=data, headers=headers, timeout=self.timeout)
            else:
                response = self.session.request(method, url, params=params, json=data, 
                                               headers=headers, timeout=self.timeout)
            
            response_time = (time.time() - start_time) * 1000  # ms
            
            try:
                response_json = response.json()
            except:
                response_json = {}
            
            return response.status_code, response_json, response_time
            
        except requests.exceptions.RequestException as e:
            response_time = (time.time() - start_time) * 1000
            return 0, {"error": str(e)}, response_time
    
    def run_test(self, name: str, category: str, method: str, path: str,
                 params: Dict = None, data: Dict = None, headers: Dict = None,
                 expected_blocked: bool = True) -> TestResult:
        """Tek bir test çalıştır"""
        status_code, response, response_time = self.test_request(method, path, params, data, headers)
        
        blocked = status_code == 403
        rule_id = response.get('rule_id')
        message = response.get('message') or response.get('error')
        
        result = TestResult(
            name=name,
            category=category,
            payload=str(params or data or path),
            expected_blocked=expected_blocked,
            actual_blocked=blocked,
            status_code=status_code,
            response_time=response_time,
            rule_id=rule_id,
            message=message
        )
        
        self.results.append(result)
        return result
    
    def print_test_result(self, result: TestResult):
        """Tek bir test sonucunu yazdır"""
        if result.actual_blocked == result.expected_blocked:
            status = f"{Fore.GREEN}✓ PASS{Style.RESET_ALL}"
        else:
            status = f"{Fore.RED}✗ FAIL{Style.RESET_ALL}"
        
        blocked_str = f"{Fore.RED}BLOCKED{Style.RESET_ALL}" if result.actual_blocked else f"{Fore.GREEN}ALLOWED{Style.RESET_ALL}"
        rule_info = f" (Rule: {result.rule_id})" if result.rule_id else ""
        
        print(f"  {status} {result.name:50} {blocked_str:10} [{result.status_code}] {result.response_time:.1f}ms{rule_info}")
    
    def run_all_tests(self):
        """Tüm testleri çalıştır"""
        print(f"\n{Back.BLUE}{Fore.WHITE} WAF Test Suite - kemal-korur {Style.RESET_ALL}\n")
        print(f"Target: {self.base_url}")
        print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        print("=" * 80)
        
        # SQL Injection Tests
        print(f"\n{Fore.CYAN}[1] SQL Injection Tests{Style.RESET_ALL}")
        print("-" * 80)
        
        self.run_test("Basic SQLi - Union Select", "SQLi", "GET", "/", 
                     {"id": "1' OR '1'='1"}, expected_blocked=True)
        self.run_test("SQLi - Union Select", "SQLi", "GET", "/", 
                     {"q": "test UNION SELECT password FROM users"}, expected_blocked=True)
        self.run_test("SQLi - Comment", "SQLi", "GET", "/", 
                     {"id": "1'--"}, expected_blocked=True)
        self.run_test("SQLi - Boolean", "SQLi", "GET", "/", 
                     {"user": "admin' AND '1'='1"}, expected_blocked=True)
        self.run_test("SQLi - Time-based", "SQLi", "GET", "/", 
                     {"id": "1' AND SLEEP(5)--"}, expected_blocked=True)
        self.run_test("SQLi - POST Body", "SQLi", "POST", "/api/login",
                     data={"password": "pass' OR '1'='1"}, expected_blocked=True)
        self.run_test("SQLi - URL Encoded", "SQLi", "GET", "/",
                     {"id": "1%27%20OR%20%271%27%3D%271"}, expected_blocked=True)
        
        for result in self.results[-7:]:
            self.print_test_result(result)
        
        # XSS Tests
        print(f"\n{Fore.CYAN}[2] XSS (Cross-Site Scripting) Tests{Style.RESET_ALL}")
        print("-" * 80)
        
        self.run_test("XSS - Script Tag", "XSS", "GET", "/",
                     {"q": "<script>alert('xss')</script>"}, expected_blocked=True)
        self.run_test("XSS - JavaScript Protocol", "XSS", "GET", "/",
                     {"url": "javascript:alert(1)"}, expected_blocked=True)
        self.run_test("XSS - Event Handler", "XSS", "GET", "/",
                     {"input": "<img src=x onerror=alert(1)>"}, expected_blocked=True)
        self.run_test("XSS - Iframe", "XSS", "GET", "/",
                     {"content": "<iframe src=evil.com></iframe>"}, expected_blocked=True)
        self.run_test("XSS - Document Cookie", "XSS", "GET", "/",
                     {"q": "test<script>document.cookie</script>"}, expected_blocked=True)
        self.run_test("XSS - POST Body", "XSS", "POST", "/api/comment",
                     data={"comment": "<script>alert('xss')</script>"}, expected_blocked=True)
        
        for result in self.results[-6:]:
            self.print_test_result(result)
        
        # Path Traversal Tests
        print(f"\n{Fore.CYAN}[3] Path Traversal Tests{Style.RESET_ALL}")
        print("-" * 80)
        
        self.run_test("LFI - Basic", "Path Traversal", "GET", "/",
                     {"file": "../../../etc/passwd"}, expected_blocked=True)
        self.run_test("LFI - Encoded", "Path Traversal", "GET", "/",
                     {"file": "..%2F..%2F..%2Fetc%2Fpasswd"}, expected_blocked=True)
        self.run_test("LFI - Null Byte", "Path Traversal", "GET", "/",
                     {"file": "../../../etc/passwd%00"}, expected_blocked=True)
        
        for result in self.results[-3:]:
            self.print_test_result(result)
        
        # Command Injection Tests
        print(f"\n{Fore.CYAN}[4] Command Injection Tests{Style.RESET_ALL}")
        print("-" * 80)
        
        self.run_test("RCE - Basic", "Command Injection", "GET", "/",
                     {"cmd": "; ls -la"}, expected_blocked=True)
        self.run_test("RCE - Pipe", "Command Injection", "GET", "/",
                     {"input": "test | cat /etc/passwd"}, expected_blocked=True)
        self.run_test("RCE - Backtick", "Command Injection", "GET", "/",
                     {"q": "test `whoami`"}, expected_blocked=True)
        
        for result in self.results[-3:]:
            self.print_test_result(result)
        
        # Normal Requests (Should Pass)
        print(f"\n{Fore.CYAN}[5] Normal Requests (Should Pass){Style.RESET_ALL}")
        print("-" * 80)
        
        self.run_test("Normal GET", "Normal", "GET", "/",
                     {"page": "home"}, expected_blocked=False)
        self.run_test("Normal POST", "Normal", "POST", "/api/users",
                     data={"name": "John", "email": "john@example.com"}, expected_blocked=False)
        self.run_test("Normal Query", "Normal", "GET", "/search",
                     {"q": "hello world"}, expected_blocked=False)
        
        for result in self.results[-3:]:
            self.print_test_result(result)
        
        # Print Summary
        self.print_summary()
    
    def print_summary(self):
        """Test özetini yazdır"""
        print("\n" + "=" * 80)
        print(f"{Back.BLUE}{Fore.WHITE} Test Summary {Style.RESET_ALL}\n")
        
        total = len(self.results)
        passed = sum(1 for r in self.results if r.actual_blocked == r.expected_blocked)
        failed = total - passed
        
        # Kategori bazında istatistikler
        categories = {}
        for result in self.results:
            if result.category not in categories:
                categories[result.category] = {'total': 0, 'passed': 0, 'failed': 0}
            categories[result.category]['total'] += 1
            if result.actual_blocked == result.expected_blocked:
                categories[result.category]['passed'] += 1
            else:
                categories[result.category]['failed'] += 1
        
        print(f"{Fore.CYAN}Overall Statistics:{Style.RESET_ALL}")
        print(f"  Total Tests: {total}")
        print(f"  {Fore.GREEN}Passed: {passed} ({passed/total*100:.1f}%){Style.RESET_ALL}")
        print(f"  {Fore.RED}Failed: {failed} ({failed/total*100:.1f}%){Style.RESET_ALL}")
        
        print(f"\n{Fore.CYAN}By Category:{Style.RESET_ALL}")
        for category, stats in sorted(categories.items()):
            pass_rate = stats['passed'] / stats['total'] * 100
            color = Fore.GREEN if pass_rate >= 80 else Fore.YELLOW if pass_rate >= 50 else Fore.RED
            print(f"  {category:20} {stats['total']:3} tests | {color}{stats['passed']:2} passed ({pass_rate:.0f}%){Style.RESET_ALL}")
        
        # Başarısız testler
        failed_tests = [r for r in self.results if r.actual_blocked != r.expected_blocked]
        if failed_tests:
            print(f"\n{Fore.RED}Failed Tests:{Style.RESET_ALL}")
            for result in failed_tests:
                expected = "BLOCKED" if result.expected_blocked else "ALLOWED"
                actual = "BLOCKED" if result.actual_blocked else "ALLOWED"
                print(f"  {Fore.RED}✗{Style.RESET_ALL} {result.name}")
                print(f"    Expected: {expected}, Got: {actual} (Status: {result.status_code})")
                if result.message:
                    print(f"    Message: {result.message}")
        
        # En yavaş testler
        slow_tests = sorted(self.results, key=lambda x: x.response_time, reverse=True)[:5]
        if slow_tests:
            print(f"\n{Fore.YELLOW}Slowest Tests:{Style.RESET_ALL}")
            for result in slow_tests:
                print(f"  {result.name:50} {result.response_time:6.1f}ms")
        
        # Rule coverage
        rule_ids = set(r.rule_id for r in self.results if r.rule_id)
        if rule_ids:
            print(f"\n{Fore.CYAN}Triggered Rules:{Style.RESET_ALL}")
            for rule_id in sorted(rule_ids):
                count = sum(1 for r in self.results if r.rule_id == rule_id)
                print(f"  Rule {rule_id:6} triggered {count} time(s)")
        
        print("\n" + "=" * 80)
        print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        
        # Exit code
        return 0 if failed == 0 else 1


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='WAF Test Suite for kemal-korur')
    parser.add_argument('--url', default='http://localhost:3000',
                       help='WAF base URL (default: http://localhost:3000)')
    parser.add_argument('--timeout', type=int, default=5,
                       help='Request timeout in seconds (default: 5)')
    parser.add_argument('--json', action='store_true',
                       help='Output results as JSON')
    
    args = parser.parse_args()
    
    tester = WAFTester(base_url=args.url, timeout=args.timeout)
    
    try:
        # Health check
        status, _, _ = tester.test_request("GET", "/health")
        if status != 200:
            print(f"{Fore.RED}Error: WAF is not responding at {args.url}{Style.RESET_ALL}")
            print(f"Status code: {status}")
            sys.exit(1)
        
        if args.json:
            # JSON output mode
            tester.run_all_tests()
            output = {
                'timestamp': datetime.now().isoformat(),
                'url': args.url,
                'total': len(tester.results),
                'passed': sum(1 for r in tester.results if r.actual_blocked == r.expected_blocked),
                'failed': sum(1 for r in tester.results if r.actual_blocked != r.expected_blocked),
                'results': [
                    {
                        'name': r.name,
                        'category': r.category,
                        'payload': r.payload,
                        'expected_blocked': r.expected_blocked,
                        'actual_blocked': r.actual_blocked,
                        'status_code': r.status_code,
                        'response_time_ms': r.response_time,
                        'rule_id': r.rule_id,
                        'message': r.message
                    }
                    for r in tester.results
                ]
            }
            print(json.dumps(output, indent=2))
        else:
            # Normal output mode
            exit_code = tester.run_all_tests()
            sys.exit(exit_code)
            
    except KeyboardInterrupt:
        print(f"\n{Fore.YELLOW}Test interrupted by user{Style.RESET_ALL}")
        sys.exit(130)
    except Exception as e:
        print(f"{Fore.RED}Error: {e}{Style.RESET_ALL}")
        sys.exit(1)


if __name__ == '__main__':
    main()

