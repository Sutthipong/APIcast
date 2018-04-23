use lib 't';
use Test::APIcast 'no_plan';

run_tests();

__DATA__

=== TEST 1: resolver

--- http_config
lua_package_path "$TEST_NGINX_LUA_PATH";
--- config
location /t {
  rewrite_by_lua_block {
    local resty_resolver = require 'resty.resolver'
    local dns_client = require 'resty.dns.resolver'

    local dns = dns_client:new{ nameservers = { { "127.0.0.1", $TEST_NGINX_RANDOM_PORT } } }
    local resolver = resty_resolver.new(dns)

    local servers = resolver:get_servers('3scale.net')
    servers.answers = nil
    ngx.ctx.upstream = servers
  }

  content_by_lua_block {
    local upstream = {}
    for _,server in ipairs(ngx.ctx.upstream) do
      table.insert(upstream, server)
    end
    ngx.say(require('cjson').encode(upstream))
  }
}
--- udp_listen random_port env chomp
$TEST_NGINX_RANDOM_PORT
--- udp_reply dns
[ "localhost", "127.0.0.1" ]
--- request
GET /t
--- response_body
[{"ttl":0,"address":"127.0.0.1"}]
--- error_code: 200


=== TEST 2: balancer

--- http_config
  lua_package_path "$TEST_NGINX_LUA_PATH";

  upstream upstream {
    server 0.0.0.1:1;

    balancer_by_lua_block {
      local balancer = require 'apicast.balancer'

      ngx.ctx.upstream = { { address = '127.0.0.1', port = $TEST_NGINX_SERVER_PORT } }

      local peers = balancer:call()
    }
    keepalive 32;
  }
--- config
location /api {
  echo 'yay';
}

location /t {
  proxy_pass http://upstream/api;
}
--- request
GET /t
--- response_body
yay
--- error_code: 200

=== TEST 3: resolver + balancer

--- http_config
  lua_package_path "$TEST_NGINX_LUA_PATH";

  upstream upstream {
    server 0.0.0.1:1;

    balancer_by_lua_block {
      local balancer = require 'apicast.balancer'
      local peers = balancer:call()
    }

    keepalive 32;
  }
--- config
location /api {
  echo 'yay';
}

location /t {
  rewrite_by_lua_block {
    local resty_resolver = require 'resty.resolver'
    local dns_client = require 'resty.dns.resolver'

    local dns = dns_client:new{ nameservers = { { "127.0.0.1", $TEST_NGINX_RANDOM_PORT } } }
    local resolver = resty_resolver.new(dns)

    ngx.ctx.upstream = resolver:get_servers('localhost', { port = $TEST_NGINX_SERVER_PORT })
  }

  proxy_pass http://upstream/api;
}
--- udp_listen random_port env chomp
$TEST_NGINX_RANDOM_PORT
--- udp_reply dns
[ "localhost", "127.0.0.1" ]
--- request
GET /t
--- response_body
yay
--- error_code: 200
