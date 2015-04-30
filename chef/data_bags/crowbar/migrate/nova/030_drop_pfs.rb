def upgrade ta, td, a, d
  %w(gitrepo git_instance git_refspec use_gitbarclamp use_pip_cache use_gitrepo use_virtualenv pfs_deps).each do |attr|
    a.delete(attr)
  end
  return a, d
end

def downgrade ta, td, a, d
  %w(gitrepo git_instance git_refspec use_gitbarclamp use_pip_cache use_gitrepo use_virtualenv pfs_deps).each do |attr|
    a[attr] = ta[attr]
  end
  return a, d
end
