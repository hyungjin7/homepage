import copy
import importlib.util
from pathlib import Path
import unittest
import yaml

spec = importlib.util.spec_from_file_location('validate_gitops', Path(__file__).parents[1] / 'validate_gitops.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class GitOpsScopeTests(unittest.TestCase):
    def setUp(self):
        self.objects = list(yaml.safe_load_all(Path('.homepage-rendered.yaml').read_text()))
    def test_current_bundle_is_valid(self):
        self.assertGreater(module.validate(self.objects), 0)
    def test_other_namespace_is_rejected(self):
        changed = copy.deepcopy(self.objects)
        next(o for o in changed if o['kind'] == 'Deployment')['metadata']['namespace'] = 'bbb-namespace'
        with self.assertRaises(AssertionError): module.validate(changed)
    def test_secret_is_not_managed(self):
        with self.assertRaises(AssertionError):
            module.validate(self.objects + [{'apiVersion':'v1','kind':'Secret','metadata':{'name':'test','namespace':'homepage'}}])
    def test_missing_configuration_is_rejected(self):
        with self.assertRaises(AssertionError):
            module.validate([o for o in self.objects if o['kind'] != 'ConfigMap'])
    def test_other_cluster_resource_is_rejected(self):
        with self.assertRaises(AssertionError):
            module.validate(self.objects + [{'apiVersion':'v1','kind':'Namespace','metadata':{'name':'other'}}])
    def test_missing_sso_is_rejected(self):
        with self.assertRaises(AssertionError):
            module.validate([o for o in self.objects if o['kind'] != 'Ingress'])
