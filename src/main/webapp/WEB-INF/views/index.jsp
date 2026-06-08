<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<!doctype html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <title>Nice PoC</title>
</head>
<body>
    <h1>첫 페이지</h1>
    <form action="${pageContext.request.contextPath}/next" method="get">
        <button type="submit">버튼</button>
    </form>
</body>
</html>
