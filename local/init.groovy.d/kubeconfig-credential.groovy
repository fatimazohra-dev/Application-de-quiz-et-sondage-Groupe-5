// Au démarrage de Jenkins : la credential "kubeconfig" pointe vers le cluster k3s local
// (celle copiée depuis la VM pointait vers Minikube). Aucune configuration manuelle.
import com.cloudbees.plugins.credentials.CredentialsProvider
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.SecretBytes
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import jenkins.model.Jenkins
import org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl

def src = new File('/k3s/kubeconfig.yaml')
for (int i = 0; i < 90 && !(src.exists() && src.length() > 0); i++) {
  sleep(2000)
}
if (!(src.exists() && src.length() > 0)) {
  println '[quiz-live] kubeconfig k3s introuvable : credential non mise à jour'
  return
}

def text = src.getText('UTF-8').replace('https://127.0.0.1:6443', 'https://k3s:6443')
def cred = new FileCredentialsImpl(CredentialsScope.GLOBAL, 'kubeconfig',
    'kubeconfig (cluster k3s local)', 'kubeconfig',
    SecretBytes.fromBytes(text.getBytes('UTF-8')))

def store = SystemCredentialsProvider.getInstance().getStore()
def old = CredentialsProvider.lookupCredentials(FileCredentialsImpl, Jenkins.get(), null, null)
    .find { it.id == 'kubeconfig' }
if (old) {
  store.updateCredentials(Domain.global(), old, cred)
} else {
  store.addCredentials(Domain.global(), cred)
}
println '[quiz-live] credential kubeconfig -> https://k3s:6443'
