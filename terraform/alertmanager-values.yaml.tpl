alertmanager:
  config:
    global:
      resolve_timeout: 5m
      smtp_smarthost: 'smtp.gmail.com:587'
      smtp_from: '${alert_email}'
      smtp_auth_username: '${alert_email}'
      smtp_auth_password: '${alert_email_password}'
      smtp_require_tls: true
    route:
      group_by: ['alertname', 'cluster', 'service']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'email-receiver'
      routes:
        - matchers:
            - 'severity="critical"'
          receiver: 'critical-email'
          continue: true
        - matchers:
            - 'severity="warning"'
          receiver: 'warning-email'
          continue: true
    receivers:
      - name: 'email-receiver'
        email_configs:
          - to: '${alert_email}'
            send_resolved: true
            headers:
              Subject: '[Alertmanager] {{ .GroupLabels.alertname }}'
      - name: 'critical-email'
        email_configs:
          - to: '${alert_email}'
            send_resolved: true
            headers:
              Subject: '[CRITICAL] {{ .GroupLabels.alertname }}'
      - name: 'warning-email'
        email_configs:
          - to: '${alert_email}'
            send_resolved: true
            headers:
              Subject: '[WARNING] {{ .GroupLabels.alertname }}'
    inhibit_rules:
      - source_matchers:
          - 'severity="critical"'
        target_matchers:
          - 'severity="warning"'
        equal: ['alertname', 'instance']
