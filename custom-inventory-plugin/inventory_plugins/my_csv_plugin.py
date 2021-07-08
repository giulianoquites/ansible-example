from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

DOCUMENTATION = r'''
    name: my_csv_plugin
    plugin_type: inventory
    short_description: Returns Ansible inventory from CSV
    description: Returns Ansible inventory from CSV
    options:
      plugin:
          description: Name of the plugin
          required: true
          choices: ['my_csv_plugin']
      path_to_inventory:
        description: Directory location of the CSV inventory
        required: true
      csv_file:
        description: File name of the CSV inventory file
        required: true
'''



from ansible.plugins.inventory import BaseInventoryPlugin
from ansible.errors import AnsibleError, AnsibleParserError
import csv


class InventoryModule(BaseInventoryPlugin):
    NAME = 'my_csv_plugin'


    def verify_file(self, path):
        '''Return true/false if this is possibly a valid file for this plugin to
consume

        '''
        valid = False
        if super(InventoryModule, self).verify_file(path):
            # base class verifies that file exists and is readable by current
            # user
            if path.endswith(('csv_inventory.yaml',
                              'csv_inventory.yml')):
                valid = True
        return valid

    def _get_structured_inventory(self, inventory_file):
    
        #Initialize a dict
        inventory_data = {}
        #Read the CSV and add it to the dictionary
        with open(inventory_file, 'r') as fh:
            csvdict = csv.DictReader(fh)
            for rows in csvdict:
                hostname = rows['SERVIDOR']
                inventory_data[hostname] = rows
        return inventory_data

    def _populate(self):
        '''Return the hosts and groups'''
        self.inventory_file = self.inv_dir + '/' + self.inv_file
        self.myinventory = self._get_structured_inventory(self.inventory_file)
        #Create the location, function and platform  groups
        locations = []
        functions = []
        platforms = []
        for data in self.myinventory.values():
            if not data['DATACENTER'] in locations:
                locations.append(data['DATACENTER'])
            if not data['RESERVADO_ANSIBLE'] in functions:
                functions.append(data['RESERVADO_ANSIBLE'])
            if not data['SISTEMA_OPERACIONAL_CMDB'] in platforms:
                platforms.append(data['SISTEMA_OPERACIONAL_CMDB'])
        for location in locations:
            self.inventory.add_group(location)
        for function in functions:
            self.inventory.add_group(function)
        for platform in platforms:
            self.inventory.add_group(platform)
        #Add the hosts to the groups
        for hostname,data in self.myinventory.items():
            self.inventory.add_host(host=hostname, group=data['DATACENTER'])
            self.inventory.add_host(host=hostname, group=data['RESERVADO_ANSIBLE'])
            self.inventory.add_host(host=hostname, group=data['SISTEMA_OPERACIONAL_CMDB'])
            self.inventory.set_variable(hostname, 'ansible_host', data['IP'])
            self.inventory.set_variable(hostname, 'ansible_network_os', data['SISTEMA_OPERACIONAL_CMDB'])
            
    
    def parse(self, inventory, loader, path, cache):
       '''Return dynamic inventory from source '''
       super(InventoryModule, self).parse(inventory, loader, path, cache)
       # Read the inventory YAML file
       self._read_config_data(path)
       try:
           # Store the options from the YAML file
           self.plugin = self.get_option('plugin')
           self.inv_dir = self.get_option('path_to_inventory')
           self.inv_file = self.get_option('csv_file')
       except Exception as e:
           raise AnsibleParserError(
               'All correct options required: {}'.format(e))
       # Call our internal helper to populate the dynamic inventory
       self._populate()
