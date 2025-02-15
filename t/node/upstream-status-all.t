#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
use t::APISIX 'no_plan';

repeat_each(1);
log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: set route(id: 1) and available upstream and show_upstream_status_in_response_header: true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: hit the route and $upstream_status is 200
--- yaml_config
apisix:
  show_upstream_status_in_response_header: true
--- request
GET /hello
--- response_body
hello world
--- response_headers
X-APISIX-Upstream-Status: 200



=== TEST 3: set route(id: 1) and set the timeout field
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin",
                        "timeout": {
                            "connect": 0.5,
                            "send": 0.5,
                            "read": 0.5
                        }
                    },
                    "uri": "/mysleep"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 4: hit routes (timeout) and $upstream_status is 504
--- yaml_config
apisix:
  show_upstream_status_in_response_header: true
--- request
GET /mysleep?seconds=1
--- error_code: 504
--- response_body eval
qr/504 Gateway Time-out/
--- response_headers
X-APISIX-Upstream-Status: 504



=== TEST 5: set route(id: 1), upstream service is not available
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: hit routes and $upstream_status is 502
--- yaml_config
apisix:
  show_upstream_status_in_response_header: true
--- request
GET /hello
--- error_code: 502
--- response_body eval
qr/502 Bad Gateway/
--- response_headers
X-APISIX-Upstream-Status: 502



=== TEST 7: set route(id: 1) and uri is `/server_error`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/server_error"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 8: hit routes and $upstream_status is 500
--- yaml_config
apisix:
  show_upstream_status_in_response_header: true
--- request
GET /server_error
--- error_code: 500
--- response_body eval
qr/500 Internal Server Error/
--- response_headers
X-APISIX-Upstream-Status: 500



=== TEST 9: set upstream(id: 1, retries = 2), has available upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.1.0.2:1": 1,
                        "127.0.0.1:1980": 1
                    },
                    "retries": 2,
                    "type": "roundrobin"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 10: set route(id: 1) and bind the upstream_id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "upstream_id": "1"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: hit routes and $upstream_status is `502, 200`
--- yaml_config
apisix:
  show_upstream_status_in_response_header: true
--- request
GET /hello
--- response_body
hello world
--- response_headers_raw_like eval
qr/X-APISIX-Upstream-Status: 502, 200|X-APISIX-Upstream-Status: 200/
--- error_log



=== TEST 12: set upstream(id: 1, retries = 2), all upstream nodes are unavailable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.3:1": 1,
                        "127.0.0.2:1": 1,
                        "127.0.0.1:1": 1

                    },
                    "retries": 2,
                    "type": "roundrobin"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 13: hit routes, retry between upstream failed, $upstream_status is `502, 502, 502`
--- yaml_config
apisix:
  show_upstream_status_in_response_header: true
--- request
GET /hello
--- error_code: 502
--- response_headers_raw_like eval
qr/X-APISIX-Upstream-Status: 502, 502, 502/



=== TEST 14: return 500 status code from APISIX
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "fault-injection": {
                            "abort": {
                                "http_status": 500,
                                "body": "Fault Injection!\n"
                            }
                        }
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 15: hit routes, status code is 500
--- yaml_config
apisix:
  show_upstream_status_in_response_header: true
--- request
GET /hello
--- error_code: 500
--- response_body
Fault Injection!
--- grep_error_log eval
qr/X-APISIX-Upstream-Status: 500/
--- grep_error_log_out



=== TEST 16: return 200 status code from APISIX
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "fault-injection": {
                            "abort": {
                                "http_status": 200,
                                "body": "Fault Injection!\n"
                            }
                        }
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 17: hit routes, status code is 200
--- yaml_config
apisix:
  show_upstream_status_in_response_header: true
--- request
GET /hello
--- response_body
Fault Injection!
--- grep_error_log eval
qr/X-APISIX-Upstream-Status: 200/
--- grep_error_log_out



=== TEST 18: return 200 status code from APISIX (with show_upstream_status_in_response_header:false)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "fault-injection": {
                            "abort": {
                                "http_status": 200,
                                "body": "Fault Injection!\n"
                            }
                        }
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 19: hit routes, status code is 200
--- yaml_config
apisix:
    show_upstream_status_in_response_header: false
--- request
GET /hello
--- response_body
Fault Injection!
--- grep_error_log eval
qr/X-APISIX-Upstream-Status: 200/
--- grep_error_log_out
