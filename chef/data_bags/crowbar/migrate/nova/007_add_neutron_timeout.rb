def upgrade ta, td, a, d
  a['neutron_url_timeout'] = ta['neutron_url_timeout']
  return a, d
end

def downgrade ta, td, a, d
  a.delete 'neutron_url_timeout'
  return a, d
end
