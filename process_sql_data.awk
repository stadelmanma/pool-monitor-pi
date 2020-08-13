BEGIN {
    n=10
    m=int((n+1)/2)
}

{val=$3*1.8+32; L[NR]=val; sum+=val}

NR>=m {
    timestamp[++i]=$1
    src_name[i]=$2
}

NR>n {sum-=L[NR-n]}

NR>=n {
    avgs[++k]=sum/n
}

END {
    for (j=1; j<=k; j++)
        printf "%s,%s,%f\n", timestamp[j],src_name[j],avgs[j]
}
