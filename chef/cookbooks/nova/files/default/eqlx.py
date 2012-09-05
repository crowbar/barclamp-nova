import sys
import functools
# TODO(aandreev): replace explicit imports with nova-based
import eventlet
import greenlet
import time
import logging

import paramiko

from nova.openstack.common import cfg
from nova.flags import FLAGS
from nova.volume.san import SanISCSIDriver


LOG = logging.getLogger(__name__)

eqlx_opts = [
    cfg.StrOpt('eqlx_group_name',
                default='group-0',
                help='Group name to use for creating volumes'),
    cfg.IntOpt('eqlx_ssh_keepalive_interval',
               default=1200,
               help='Seconds to wait before sending a keepalive packet'),
    cfg.IntOpt('eqlx_cli_timeout',
               default=30,
               help='Timeout for the Group Manager cli command execution'),
    cfg.IntOpt('eqlx_cli_max_retries',
               default=5,
               help='Maximum retry count for reconnection'),
    cfg.IntOpt('eqlx_cli_retries_timeout',
               default=30,
               help='Seconds to sleep before the next reconnection retry'),
    cfg.BoolOpt('eqlx_use_chap',
                default=False,
                help='Use CHAP authentificaion for targets?'),
    cfg.StrOpt('eqlx_chap_login',
                default='admin',
                help='Existing CHAP account name'),
    cfg.StrOpt('eqlx_chap_password',
                default='password',
                help='Password for specified CHAP account name'),
    cfg.BoolOpt('eqlx_verbose_ssh',
            default=False,
            help='Print SSH debugging output to stderr'),
    ]

if __name__ != '__main__':
    FLAGS.register_opts(eqlx_opts)


class Timeout(Exception):
    pass

def with_timeout(f):
    @functools.wraps(f)
    def __inner(self, *args, **kwargs):
        timeout = kwargs.pop('timeout', None)
        gt = eventlet.spawn(f, self, *args, **kwargs)
        if timeout is None:
            return gt.wait()
        else:
            kill_thread = eventlet.spawn_after(timeout, gt.kill)
            try:
                res = gt.wait()
            except greenlet.GreenletExit:
                raise Timeout()
            else:
                kill_thread.cancel()
                return res

    return __inner

def monkey_patch_eventlet():
    """This monkey patch provides a workaround for the  
    ('_GreenThread' object has no attribute 'daemon') issue seen when using paramiko 
    together with eventlet library of version less then 0.9.17
    """
    import threading, eventlet

    if eventlet.__version__ < '0.9.17':
        _current_thread = threading.current_thread
        def current_thread():
            thread = _current_thread()
            thread.__dict__['daemon'] = True
            return thread
        threading.current_thread = current_thread

class DellEQLSanISCSIDriver(SanISCSIDriver):
    """Implements commands for Dell EqualLogic SAN ISCSI management.
    
    To enable the driver add the following line to the nova configuration:
        volume_driver=nova.volume.san.DellEQLSanISCSIDriver

    Driver's prerequisites are:
        - a separate volume group set up and running on the SAN
        - SSH access to the SAN
        - a special user must be created which must be able to
            - create/delete volumes and snapshots;
            - clone snapshots into volumes; 
            - modify volume access records;
    
    The access credentials to the SAN are provided by means of the following flags
        san_ip=<ip_address>
        san_login=<user name>
        san_password=<user password>

    Thin provision of volumes is enabled by default, to disable it use:
        san_thin_provision=false

    In order to use target CHAP authentication (which is disabled by default) SAN 
    administrator must create a local CHAP user and specify the following flags 
    for the driver:
        eqlx_use_chap=true
        eqlx_chap_login=<chap_login>
        eqlx_chap_password=<chap_password>

    eqlx_group_name parameter actually represents the CLI prompt message without '>'
    ending. E.g. if prompt looks like 'group-0>', then the parameter must be set to 
    'group-0'

    To adjust default 1200 secs ssh keep alive packets sending interval use
        eqlx_ssh_keepalive_interval=<seconds>

    Also, the default CLI command execution timeout is 30 secs. Adjustable by
        eqlx_cli_timeout=<seconds>

    In addition to enable SSH connection debugging output use the flag:
        eqlx_verbose_ssh=True
    """

    def __init__(self):
        super(DellEQLSanISCSIDriver, self).__init__()
        
        if FLAGS.eqlx_verbose_ssh:
            logger = paramiko.util.logging.getLogger("paramiko")
            logger.setLevel(paramiko.util.DEBUG)
            logger.addHandler(paramiko.util.logging.StreamHandler(sys.stdout))

        monkey_patch_eventlet()

    def _connect_to_ssh(self):
        # NOTE(aandreev): storing a stong reference to the client to avoid 
        # it's removal by the garbage collection. paramiko is weird!
        self.ssh_client = super(DellEQLSanISCSIDriver, self)._connect_to_ssh()
        transport = self.ssh_client.get_transport()
        transport.set_keepalive(FLAGS.eqlx_ssh_keepalive_interval)
        return transport

    def _check_connection(self):
        for try_no in range(FLAGS.eqlx_cli_max_retries):
            if hasattr(self, 'ssh'):
                try:
                    self._run_ssh('cli-settings', 'show',
                                 timeout=FLAGS.eqlx_cli_timeout)
                except Exception as error:
                    LOG.debug(error)
                    LOG.info(_("Connection to SAN has been lost"))
                    delattr(self, 'ssh')
                else:
                    LOG.debug(_("SAN connection is up"))
                    return 
            if try_no:
                time.sleep(FLAGS.eqlx_cli_retries_timeout)
            try:
                LOG.debug(_("Connecting to the SAN (%s@%s:%d)"), FLAGS.san_login, 
                    FLAGS.san_ip, FLAGS.san_ssh_port)
                self.ssh = self._connect_to_ssh()
                LOG.info(_("Connected to the SAN after %d retries"), try_no)
            except Exception as error:
                LOG.debug(error)
                LOG.error(_("Failed to connect to the SAN"))
            else:
                return

        msg = _("unable to connect to the EQL appliance after %(try_no)d retries") % locals()
        raise exception.Error(msg)

    def set_execute(self, execute):
        """The only possible method of command exection here is SSH"""
        pass
    
    def _execute(self, *args, **kwargs):
        command = ' '.join(args)
        try:
            self._check_connection()
            LOG.info(_('executing "%s"') % command)
            return self._run_ssh(command, timeout=FLAGS.eqlx_cli_timeout)
        except Timeout:
            msg = _("Timeout while executing EQL command: %(command)s") % \
                                                                       locals()
            raise exception.Error(msg)

    @with_timeout
    def _run_ssh(self, command, check_exit_code=True):
        chan = self.ssh.open_session()
        chan.invoke_shell()
        
        if FLAGS.eqlx_verbose_ssh:
            LOG.debug(_("Reading CLI MOTD"))
        motd = self._get_output(chan)
        
        cmd = "%s %s %s" % ('stty', 'columns', '255')
        if FLAGS.eqlx_verbose_ssh:
            LOG.debug(_("Setting CLI terminal width: '%s'"), cmd)
        chan.send(cmd + '\r')
        out = self._get_output(chan)
        
        if FLAGS.eqlx_verbose_ssh:
            LOG.debug(_("Sending CLI command: '%s'"), command)
        chan.send(command + '\r')
        out = self._get_output(chan)
        
        chan.close()
        
        if any(line.startswith('% Error') for line in out):
            msg = _("Error executing EQL command: %(cmd)s") % locals()
            raise exception.Error(msg, out)
        return out

    def _get_output(self, chan):
        out = ''
        ending = '%s> ' % FLAGS.eqlx_group_name
        while not out.endswith(ending):
            out += chan.recv(102400)

        out = out.splitlines()
        if FLAGS.eqlx_verbose_ssh:
            LOG.debug(_("CLI output"))
            for line in out:
                LOG.debug("%s #", line)

        return out

    def _get_prefixed_value(self, lines, prefix):
        for line in lines:
            if line.startswith(prefix):
                return line[len(prefix):]
        return None

    def _get_volume_data(self, lines):
        prefix = 'iSCSI target name is '
        target_name = self._get_prefixed_value(lines, prefix)[:-1]
        lun_id = "%s:%s,1 %s 0" % (self._group_ip, '3260', target_name)
        model_update = {}
        model_update['provider_location'] = lun_id
        if FLAGS.eqlx_use_chap:
            model_update['provider_auth'] = 'CHAP %s %s' % \
                    (FLAGS.eqlx_chap_login, FLAGS.eqlx_chap_password)
        return model_update

    def do_setup(self, context):
        """Disable cli confirmation and tune output format"""
        disabled_cli_features = ('confirmation', 'paging', 'events',
                                 'formatoutput')
        for feature in disabled_cli_features:
            self._execute('cli-settings', feature, 'off')
        
        
        for line in self._execute('grpparams', 'show'):
            if line.startswith('Group-Ipaddress:'):
                _nop, _nop, self._group_ip = line.rstrip().partition(' ')

        LOG.info(_("Setup is complete, group IP is %s"), self._group_ip)

    def create_volume(self, volume):
        """Create a volume"""
        cmd = ['volume', 'create', volume['name'], "%sG" % (volume['size'],)]
        if FLAGS.san_thin_provision:
            cmd.append('thin-provision')
        out = self._execute(*cmd)
        return self._get_volume_data(out)

    def delete_volume(self, volume):
        """Delete a volume"""
        self._execute('volume', 'select', volume['name'], 'offline')
        self._execute('volume', 'delete', volume['name'])

    def create_snapshot(self, snapshot):
        """"Create snapshot of existing volume on appliance"""
        out = self._execute('volume', 'select', snapshot['volume_name'],
                                  'snapshot', 'create-now')
        prefix = 'Snapshot name is '
        snap_name = self._get_prefixed_value(out, prefix)
        self._execute('volume', 'select', snapshot['volume_name'],
                            'snapshot', 'rename', snap_name, snapshot['name'])

    def create_volume_from_snapshot(self, volume, snapshot):
        """Create new volume from other volume's snapshot on appliance"""
        out = self._execute('volume', 'select', snapshot['volume_name'],
                                  'snapshot', 'select', snapshot['name'],
                                  'clone', volume['name'])
        return self._get_volume_data(out)

    def delete_snapshot(self, snapshot):
        """Delete volume's snapshot"""
        self._execute('volume', 'select', snapshot['volume_name'],
                            'snapshot', 'delete', snapshot['name'])

    def initialize_connection(self, volume, connector):
        """Restrict access to a volume"""
        cmd = ['volume', 'select', volume['name'], 'access', 'create',
               'initiator', connector['initiator']]
        if FLAGS.eqlx_use_chap:
            cmd.extend(['authmethod chap', 'username', FLAGS.eqlx_chap_login])
        self._execute(*cmd)
        iscsi_properties = self._get_iscsi_properties(volume)
        return {
            'driver_volume_type': 'iscsi',
            'data': iscsi_properties
        }

    def terminate_connection(self, volume, connector):
        """Remove access restictions from a volume"""
        self._execute('volume', 'select', volume['name'],
                            'access', 'delete', '1')

    def create_export(self, context, volume):
        """Create an export of a volume
        Driver has nothing to do here for the volume has been exported
        already by the SAN, right after it's creation.
        """
        pass

    def ensure_export(self, context, volume):
        """Ensure an export of a volume
        Driver has nothing to do here for the volume has been exported
        already by the SAN, right after it's creation.
        """
        pass

    def remove_export(self, context, volume):
        """Remove an export of a volume
        Driver has nothing to do here for the volume has been exported
        already by the SAN, right after it's creation.
        Nothing to remove since there's nothing exported.
        """
        pass

    def local_path(self, volume):
        raise NotImplementedError()

if __name__ == "__main__":
    """The following code make it possible to execute a set of arbitrary commands 
    on the SAN without starting up the nova-volume service. The script requires no 
    additional configuration beyond one already used by regular nova services.
    To run the script use the following command line:

    python <nova-pkg-dir>/volume/san.py [--config=<optional-file-with-extra-cfg>] <cmd1> ... <cmdN>

    NOTE: when working with the source packaged nova use the command line

    cd <nova-src-dir> && python nova/volume/san.py ...
    """
    utils.default_flagfile()
    args = flags.FLAGS(sys.argv)
    logging.setup()
    
    utils.monkey_patch()
    volume_driver = utils.import_object(FLAGS.volume_driver)
    
    volume_driver.do_setup(None)
    volume_driver.check_for_setup_error()

    for command in args[1:]:
        sys.stdout.write('\n'.join(volume_driver._execute(command)))
