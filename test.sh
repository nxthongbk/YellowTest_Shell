#!/bin/bash -x
c = 0

if $c
then
	echo "true statement"
else
	echo "false statement"
fi

tArray=(
	the
	quick
	'brown fox'
	"jump over"
	the
	lazy
	dog
)

for t in "${tArray[@]}"
do
	echo $t
done
