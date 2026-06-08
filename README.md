# Nice PoC

Spring Boot + JSP minimal web page.

## Pages

- `/` - button page
- `/next` - shows `버튼이 작동합니다`

## Run

```bash
mvn spring-boot:run
```

Open:

```text
http://localhost:8080/
```

## Build WAR

```bash
mvn clean package
```

WAR output:

```text
target/nice-poc.war
```
