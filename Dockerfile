FROM ubuntu:latest

RUN apt update && apt install -y python3-full

CMD ["python3", "-m", "http.server"]
