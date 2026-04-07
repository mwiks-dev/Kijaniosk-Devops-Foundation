# kk-payments Hardening Log

## Objective
The objective of this exercise was to confirm that `kk-payments.service` meets the project requirement of a `systemd-analyze security` score below 2.5 while still loading its configuration correctly and starting successfully.

For this project, the hardening score matters, but service correctness matters more. A low score is only useful if the service can still read its environment file, start cleanly, and operate within the intended access model.

## Starting point
The initial `systemd-analyze security` score for `kk-payments.service` on this VM was **1.9**.

This already satisfied the project requirement, which is a score **below 2.5** for the payments service.

Because the target was already met, I did not apply additional hardening directives purely to make the number lower. Instead, I validated that the current unit file was already appropriately hardened, confirmed that it still functioned correctly, and documented directives I investigated but intentionally chose not to change.

## Validation checks performed
Before accepting the unit as complete, I verified the following:

1. The payments service account could read its environment file.
2. The unit file reloaded correctly after validation.
3. The service restarted successfully.
4. The final score remained below the required threshold.
5. The current hardening profile did not break configuration loading or service startup.

Validation commands used:

```bash
sudo -u kk-payments cat /opt/kijanikiosk/config/payments-api.env
sudo systemctl daemon-reload
sudo systemctl restart kk-payments.service
sudo systemctl status kk-payments.service --no-pager
sudo systemd-analyze security kk-payments.service

## Evidence
![output for `sudo systemd-analyze security kk-payments.service`](Screenshots/Screenshot from 2026-04-07 15-25-10.png)
