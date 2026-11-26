"""Validate rendered Homepage manifests without contacting a cluster."""
from pathlib import Path
import sys
import yaml

CLUSTER = {('Namespace', 'homepage'), ('ClusterRole', 'homepage-readonly'),
           ('ClusterRoleBinding', 'homepage-readonly')}
NAMESPACED = {'ConfigMap', 'ServiceAccount', 'Service', 'Deployment', 'Ingress', 'Middleware'}

def validate(objects):
    objects = [o for o in objects if o]
    seen = set()
    configmaps = set()
    deployment = None
    for obj in objects:
        kind, meta = obj.get('kind'), obj.get('metadata', {})
        name, namespace = meta.get('name'), meta.get('namespace')
        assert name and obj.get('apiVersion'), 'Unnamed or unversioned resource'
        identity = (kind, namespace, name)
        assert identity not in seen, 'Duplicate resource: ' + str(identity)
        seen.add(identity)
        if kind in ('Namespace', 'ClusterRole', 'ClusterRoleBinding'):
            assert (kind, name) in CLUSTER, 'Unexpected cluster resource: ' + str(identity)
        else:
            assert kind in NAMESPACED and namespace == 'homepage', 'Outside Homepage scope: ' + str(identity)
        if kind == 'ConfigMap':
            configmaps.add(name)
            for key, value in obj.get('data', {}).items():
                if key.endswith(('.yaml', '.yml')):
                    yaml.safe_load(value)
        if kind == 'Deployment':
            assert name == 'homepage', 'Unexpected deployment'
            deployment = obj
    assert deployment, 'Homepage deployment is missing'
    spec = deployment['spec']['template']['spec']
    ref = next(v['configMap']['name'] for v in spec['volumes'] if v['name'] == 'config')
    assert ref in configmaps, 'Generated configuration is not mounted'
    assert any(o.get('kind') == 'Ingress' and o['metadata']['name'] == 'homepage-ingress'
               and o['metadata'].get('annotations', {}).get('traefik.ingress.kubernetes.io/router.middlewares')
               == 'homepage-homepage-sso@kubernetescrd' for o in objects), 'Homepage SSO protection is missing'
    return len(objects)

if __name__ == '__main__':
    print('Validated Homepage resources:', validate(yaml.safe_load_all(Path(sys.argv[1]).read_text())))
