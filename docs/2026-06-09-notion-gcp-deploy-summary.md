# GCP Tomcat + GitHub Actions 배포 정리

## 목적

Spring Boot + JSP로 만든 간단한 WAR 애플리케이션을 GCP VM의 Tomcat10에 배포한다.

배포는 GitHub Actions self-hosted runner로 자동화한다.

## 전체 흐름

```text
로컬 PC에서 코드 수정
-> GitHub main 브랜치로 push
-> GitHub Actions 실행
-> GCP VM의 self-hosted runner가 job 수행
-> Maven build
-> target/nice-poc.war 생성
-> /var/lib/tomcat10/webapps/ROOT.war로 배포
-> Tomcat10 재시작
-> http://GCP_PUBLIC_IP:8080/ 접속
```

## 현재 프로젝트

- Framework: Spring Boot
- View: JSP
- Packaging: WAR
- Java: 17
- Build tool: Maven
- Target server: Tomcat10

현재 페이지:

```text
/      -> 버튼 페이지
/next  -> "버튼이 작동합니다" 출력 페이지
```

## GCP VM 구성

필요 구성:

- Ubuntu VM
- Java 17
- Maven
- Tomcat10
- GitHub Actions self-hosted runner

필요 포트:

- SSH: 22
- Tomcat: 8080

GCP 방화벽에서 8080 포트를 허용해야 외부에서 웹페이지를 확인할 수 있다.

## Tomcat 경로

Ubuntu 패키지 설치 기준:

```text
CATALINA_HOME = /usr/share/tomcat10
CATALINA_BASE = /var/lib/tomcat10
설정 파일 = /etc/tomcat10
배포 경로 = /var/lib/tomcat10/webapps
서비스명 = tomcat10
```

WAR 배포 경로:

```text
/var/lib/tomcat10/webapps/ROOT.war
```

ROOT.war로 배포하면 접속 주소는 다음과 같다.

```text
http://GCP_PUBLIC_IP:8080/
```

## GitHub Actions Runner

runner는 GCP VM에 설치한다.

workflow의 runner 조건:

```yaml
runs-on:
  - self-hosted
  - Linux
  - x64
  - gcp
  - tomcat
```

GCP VM runner에도 `gcp`, `tomcat` label이 있어야 한다.

runner 상태:

```text
Idle = 정상 대기
Busy = workflow 실행 중
Offline = 연결 끊김
```

## Workflow 역할

현재 `.github/workflows/deploy.yml`은 다음 작업을 한다.

```text
1. GitHub repository checkout
2. runner 환경 확인
3. Maven으로 WAR 빌드
4. Tomcat10 중지
5. 기존 ROOT.war와 ROOT 디렉터리 삭제
6. target/nice-poc.war를 ROOT.war로 복사
7. Tomcat10 시작
8. webapps 배포 파일 확인
```

## 주의할 점

Maven이 없으면 다음 오류가 난다.

```text
mvn: command not found
```

해결:

```bash
sudo apt update
sudo apt install -y maven
mvn -version
```

sudo 권한이 없으면 다음 오류가 난다.

```text
sudo: a password is required
```

해결 방향:

```text
runner 실행 사용자에게 Tomcat 제어와 webapps 배포에 필요한 명령만 NOPASSWD로 허용한다.
```

검증:

```bash
sudo -k
sudo -n /usr/bin/systemctl stop tomcat10
sudo -n /usr/bin/systemctl start tomcat10
sudo -n /usr/bin/systemctl status tomcat10 --no-pager
```

## 다음 체크리스트

- GCP VM에 Java 17 설치 확인
- GCP VM에 Maven 설치 확인
- GCP VM에 Tomcat10 설치 확인
- Tomcat이 8080에서 실행되는지 확인
- GCP 방화벽에서 8080 허용
- GCP VM에 GitHub Actions runner 서비스 등록
- runner label에 `gcp`, `tomcat` 추가
- sudoers에서 runner 사용자 권한 설정
- GitHub Actions 수동 실행
- `http://GCP_PUBLIC_IP:8080/` 접속 확인
