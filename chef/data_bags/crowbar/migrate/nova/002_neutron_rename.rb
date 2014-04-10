
def upgrade ta, td, a, d
  a['networking_backend'] = "neutron" if a['networking_backend'] == "quantum"
  if a['quantum_metadata_proxy_shared_secret']
    a['neutron_metadata_proxy_shared_secret'] = a['quantum_metadata_proxy_shared_secret']
    a.delete 'quantum_metadata_proxy_shared_secret'
  end
  if a['quantum_instance']
    a['neutron_instance'] = a['quantum_instance']
    a.delete 'quantum_instance'
  end
  ### Delete Quantum Keystone endpoint here
  return a, d
end

def downgrade ta, td, a, d
  a['networking_backend'] = "quantum" if a['networking_backend'] == "neutron"
  if a['neutron_metadata_proxy_shared_secret']
    a['quantum_metadata_proxy_shared_secret'] = a['neutron_metadata_proxy_shared_secret']
    a.delete 'neutron_metadata_proxy_shared_secret'
  end
  if a['neutron_instance']
    a['quantum_instance'] = a['neutron_instance']
    a.delete 'neutron_instance'
  end
  ### Delete Neutron Keystone endpoint here
  return a, d
end
