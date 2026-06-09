# GitHub Actions Runner 권한 문제 보고서

## 1. 문서 목적

GCP VM에 설치한 GitHub Actions self-hosted runner가 Tomcat10 배포 workflow를 실행할 때 발생한 sudo 권한 문제를 정리한다.

이 문서는 다음 내용을 기록한다.

- 발생 증상
- 실제 Actions 로그 해석
- 원인 분석
- sudoers 설정 방향
- deploy.yml 수정 방향
- 검증 명령
- 재발 방지 체크리스트

## 2. 배포 환경

현재 배포 구조는 다음과 같다.

```text
GitHub repository
-> GitHub Actions workflow
-> GCP VM의 self-hosted runner
-> Maven WAR build
-> GCP VM의 Tomcat10 webapps에 ROOT.war 배포
```

주요 값:

```text
Runner user = hojin9014
Tomcat service = tomcat10
Tomcat deploy path = /var/lib/tomcat10/webapps
Build artifact = target/nice-poc.war
Deploy artifact = /var/lib/tomcat10/webapps/ROOT.war
```

## 3. 발생 증상

GitHub Actions의 `Start Tomcat` 단계에서 다음 오류가 발생했다.

```text
sudo: a password is required
Error: Process completed with exit code 1.
```

문제가 발생한 명령은 다음과 같았다.

```bash
sudo -n /usr/bin/systemctl start tomcat10
```

여기서 `sudo -n`은 비밀번호를 묻지 말고, 권한이 없으면 즉시 실패하라는 의미다.

즉 이 오류는 다음 의미다.

```text
GitHub Actions runner 환경에서
해당 sudo 명령은 비밀번호 없이 실행할 권한이 없다.
```

## 4. 혼동 지점

Actions 로그의 다음 부분은 성공을 의미하지 않는다.

```text
Evaluating: success()
=> true
Starting: Start Tomcat
```

이 로그는 이전 step들이 성공했으므로 `Start Tomcat` step을 실행한다는 뜻이다.

실제 성공 여부는 그 아래 명령 실행 결과를 봐야 한다.

```text
sudo: a password is required
Error: Process completed with exit code 1.
```

따라서 해당 step은 실패한 것이 맞다.

## 5. 진단 결과

runner 내부에서 다음 진단 step을 실행했다.

```yaml
- name: Debug sudo in runner
  run: |
    whoami
    id
    groups
    sudo -n -l
    sudo -k
    sudo -n whoami
    sudo -n /usr/bin/systemctl status tomcat10 --no-pager
```

Actions 로그에서 확인된 실행 사용자는 다음과 같다.

```text
whoami -> hojin9014
```

즉 runner는 예상대로 `hojin9014` 사용자로 실행되고 있었다.

Actions 로그에서 확인된 sudoers 권한은 다음과 같았다.

```text
User hojin9014 may run the following commands:
    (root) NOPASSWD: /bin/systemctl stop tomcat10,
                     /bin/systemctl start tomcat10,
                     /bin/systemctl status tomcat10,
                     /usr/bin/rm,
                     /usr/bin/cp,
                     /usr/bin/chown,
                     /bin/rm,
                     /bin/cp,
                     /bin/chown
```

여기서 핵심은 `systemctl` 경로다.

```text
sudoers에서 허용한 경로 = /bin/systemctl
workflow에서 실행한 경로 = /usr/bin/systemctl
```

sudoers는 명령의 전체 경로와 인자까지 기준으로 매칭한다.

따라서 `/bin/systemctl start tomcat10`은 허용되어도 `/usr/bin/systemctl start tomcat10`은 별도 허용이 없으면 실패할 수 있다.

## 6. sudo -n whoami 실패의 의미

진단 step에서 다음 명령도 실패했다.

```bash
sudo -n whoami
```

이 실패는 정상적인 진단 결과다.

현재 sudoers에는 `whoami` 명령이 NOPASSWD로 허용되어 있지 않기 때문이다.

즉 이 결과는 다음 의미가 아니다.

```text
sudo 전체가 불가능하다
```

실제 의미는 다음과 같다.

```text
허용 목록에 없는 명령은 비밀번호 없이 sudo 실행할 수 없다.
```

## 7. 근본 원인

근본 원인은 다음과 같다.

```text
GitHub Actions workflow는 /usr/bin/systemctl을 실행했지만,
sudoers에는 /bin/systemctl만 NOPASSWD로 허용되어 있었다.
```

그 결과 Actions runner는 `systemctl start tomcat10`을 실행할 때 비밀번호를 요구했고, Actions는 비대화형 환경이라 비밀번호를 입력할 수 없어 실패했다.

## 8. 해결 방법 A - deploy.yml을 sudoers에 맞추기

sudoers에 이미 `/bin/systemctl`이 허용되어 있으므로, workflow에서 systemctl 경로를 `/bin/systemctl`로 바꾸는 방법이다.

예시:

```yaml
- name: Stop Tomcat
  run: |
    sudo -n /bin/systemctl stop "$TOMCAT_SERVICE"

- name: Start Tomcat
  run: |
    sudo -n /bin/systemctl start "$TOMCAT_SERVICE"
    sudo -n /bin/systemctl status "$TOMCAT_SERVICE" --no-pager
```

장점:

```text
sudoers 수정 없이 workflow만 수정하면 된다.
```

주의:

```text
GCP VM에서 실제 systemctl 경로가 /bin/systemctl인지 확인해야 한다.
```

확인 명령:

```bash
command -v systemctl
ls -l /bin/systemctl
ls -l /usr/bin/systemctl
```

## 9. 해결 방법 B - sudoers에 /usr/bin/systemctl 추가

현재 deploy.yml의 `/usr/bin/systemctl`을 유지하려면 sudoers에 `/usr/bin/systemctl`도 허용한다.

수정 명령:

```bash
sudo visudo -f /etc/sudoers.d/github-runner-tomcat
```

권장 설정:

```sudoers
hojin9014 ALL=(root) NOPASSWD: /bin/systemctl stop tomcat10, /bin/systemctl start tomcat10, /bin/systemctl status tomcat10, /usr/bin/systemctl stop tomcat10, /usr/bin/systemctl start tomcat10, /usr/bin/systemctl status tomcat10, /usr/bin/rm, /usr/bin/cp, /usr/bin/chown, /bin/rm, /bin/cp, /bin/chown
```

문법 검사:

```bash
sudo visudo -c
```

검증:

```bash
sudo -k
sudo -n /usr/bin/systemctl start tomcat10
sudo -n /usr/bin/systemctl status tomcat10 --no-pager
```

## 10. 권장 방식

현재 상황에서는 두 방법 모두 가능하다.

다만 운영 안정성을 생각하면 다음 중 하나로 통일해야 한다.

```text
방법 A: workflow를 /bin/systemctl로 통일
방법 B: sudoers에 /usr/bin/systemctl도 추가하고 workflow는 그대로 유지
```

중요한 것은 workflow에서 실행하는 명령 경로와 sudoers에 허용한 명령 경로가 정확히 일치해야 한다는 점이다.

## 11. 보안상 주의사항

deploy.yml에 root 비밀번호나 사용자 비밀번호를 직접 작성하지 않는다.

권장하지 않는 방식:

```yaml
echo "password" | sudo -S systemctl start tomcat10
```

이 방식은 GitHub Actions 로그, repository 이력, secret 관리 실수로 비밀번호가 노출될 수 있다.

권장 방식은 다음과 같다.

```text
필요한 명령만 sudoers에서 NOPASSWD로 제한 허용한다.
```

예를 들어 Tomcat 배포에는 다음 정도만 허용하면 된다.

```text
systemctl stop/start/status tomcat10
rm
cp
chown
```

## 12. 최종 검증 체크리스트

GCP VM 터미널에서 다음을 확인한다.

```bash
whoami
```

예상:

```text
hojin9014
```

sudoers 확인:

```bash
sudo -l
```

Actions에서 실행하는 명령이 `NOPASSWD` 목록에 있는지 확인한다.

sudo 캐시 제거 후 검증:

```bash
sudo -k
sudo -n /usr/bin/systemctl stop tomcat10
sudo -n /usr/bin/systemctl start tomcat10
sudo -n /usr/bin/systemctl status tomcat10 --no-pager
```

만약 workflow를 `/bin/systemctl`로 수정했다면 다음으로 검증한다.

```bash
sudo -k
sudo -n /bin/systemctl stop tomcat10
sudo -n /bin/systemctl start tomcat10
sudo -n /bin/systemctl status tomcat10 --no-pager
```

GitHub Actions 로그에서 확인할 것:

```text
whoami = hojin9014
sudo -n -l 결과에 workflow 명령이 포함되어 있음
Start Tomcat step에서 sudo: a password is required 오류가 없음
```

## 13. 결론

이번 권한 문제는 runner 사용자가 틀린 문제가 아니라, sudoers에 허용된 명령 경로와 deploy.yml에서 실행한 명령 경로가 일치하지 않아 발생한 문제다.

핵심 정리는 다음과 같다.

```text
runner user = hojin9014
sudoers 허용 = /bin/systemctl start tomcat10
workflow 실행 = /usr/bin/systemctl start tomcat10
결과 = NOPASSWD 매칭 실패로 sudo password 요구
```

따라서 해결은 다음 중 하나다.

```text
1. deploy.yml을 /bin/systemctl로 수정
2. sudoers에 /usr/bin/systemctl start/stop/status tomcat10 추가
```

비밀번호를 workflow에 넣는 방식은 사용하지 않는다.
