#!/bin/bash

URL="${1:-http://23.20.63.231:30080}"
CONCURRENT="${2:-3}"
DELAY="${3:-0.5}"

ENDPOINTS=(
  "/"
  "/product/OLJCESPC7Z"
  "/product/66VCHSJNUP"
  "/product/1YMWWN1N4O"
  "/product/L9ECAV7KIM"
  "/cart"
  "/product/2ZYFJ3GM2N"
  "/product/0PUK6V6EKW"
  "/product/LS4PSXUNUM"
)

CART_PRODUCTS=(
  "OLJCESPC7Z"
  "66VCHSJNUP"
  "1YMWWN1N4O"
  "L9ECAV7KIM"
)

echo "   Boutique load generator"
echo "   URL: $URL"
echo "   Concurrent workers: $CONCURRENT"
echo "   Delay: ${DELAY}s"
echo ""

COUNTER=0
ERRORS=0

worker() {
  while true; do
    # Losowy endpoint
    ENDPOINT="${ENDPOINTS[$RANDOM % ${#ENDPOINTS[@]}]}"
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$URL$ENDPOINT")

    if [[ "$STATUS" =~ ^[23] ]]; then
      echo "Successful: GET $ENDPOINT [$STATUS]"
    else
      echo "Error: GET $ENDPOINT [$STATUS]"
    fi

    sleep "$DELAY"
  done
}

for i in $(seq 1 "$CONCURRENT"); do
  worker &
done

trap 'echo ""; echo "Stopping..."; kill $(jobs -p) 2>/dev/null; exit 0' INT TERM
wait
