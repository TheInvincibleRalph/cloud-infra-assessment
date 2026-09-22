# Demonstration Application

`server.py` is the application deployed to every EC2 instance in the Auto Scaling group. It uses only Python's standard library, so private instances do not need internet access to install dependencies.

Endpoints:

- `GET /` returns an HTML page containing the project, environment, and serving instance hostname.
- `GET /health` returns `{"status": "healthy"}` for the ALB target-group health check.

Run it locally from this directory:

```bash
PORT=8080 PROJECT=cloud-engineer-assessment ENVIRONMENT=local python3 server.py
```

In another terminal:

```bash
curl http://localhost:8080/
curl http://localhost:8080/health
```

The production Terraform configuration base64-encodes this exact file and passes it to `user-data.sh.tftpl`. At instance boot, cloud-init writes it to `/opt/assessment-app/server.py` and starts it as a systemd service.

