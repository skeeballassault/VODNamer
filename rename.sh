a=1
for i in ${1}*.mp4; do
  new=$(printf "%04d.mp4" "$a") #04 pad to length of 4
  mv -i -- "$i" "${1}$new"
  let a=a+1
done
