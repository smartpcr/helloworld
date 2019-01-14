curl -sL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin
linkerd version

linkerd check --pre
linkerd install | kubectl apply -f -
linkerd check

linkerd dashboard

# generate traffic
linkerd -n linkerd top deploy/linkerd-web