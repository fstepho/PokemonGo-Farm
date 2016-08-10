// app/AppKernel.php
public function registerBundles()
{
    $bundles = array(
        new HWI\Bundle\OAuthBundle\HWIOAuthBundle(),
    );
    return $bundles;
}