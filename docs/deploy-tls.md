# dsh web 面部署：HTTPS 监听与绑定地址（0.2.1 起原生支持）

适用版本：dsh 运行时 ≥ 0.2.1-alpha.2（`webserver` 的 `tls` 与具体 `host` 绑定）。

数字分身套件的三个 HTTP 面插件（dsh-redact 配置页、dsh-memory 管理页、dsh-yuyi hub
websocket upgrade）走宿主 `webServer` 的 `kind: 'exact'` 路由，**路由契约未变**——
TLS 与绑定是宿主 webserver 的部署配置，插件零改动。

## 组合配置（profile 补丁）

在 profile 的组合文件（`cordis.patch.yml` / 壳生成的 profile）里给 webserver 条目加配置：

```yaml
- id: webserver
  config:
    # 具体接口地址（IPv4/IPv6 字面量；通配地址在加载期被拒绝）
    host: 10.0.0.7
    port: 443
    # 原生 TLS：PEM 证书，绑定时读一次；加载失败直接拒绝初始化，不回退 HTTP
    tls:
      certFile: ./certs/chain.pem
      keyFile: ./certs/key.pem
    # compression 可选
```

## 注意事项

- **通配地址（0.0.0.0 / ::）会被加载期拒绝**——必须写具体地址（多网卡机器写
  目标网卡地址；本机回环场景保持默认，不需要本配置）。
- **证书替换需重启 webserver**（PEM 在绑定时读一次，无运行时 reload）。
- 端口 443 需要相应权限（Linux 上非 root 需 cap_net_bind_service 或前端反代）。
- 前置反代（nginx/caddy）方案不受影响：继续用反代终结 TLS 时不要配 `tls` 段。
- 插件侧深链（如 im-bot 的通知链接）应使用对外可达地址；0.2.1 的
  `--public-url`（web-app）可声明对外根，会话内注入 `DSH_WEB_URL` 环境变量。

## 与套件安装器的关系

`install-all.bat` 停止的「dsh web 服务」即监听该地址的进程——TLS 证书文件的
更换窗口与套件安装窗口一致（服务停态下替换证书文件最稳妥）。
