(function(){
  const SUPABASE_URL='https://hennzggqaquevqgiucqn.supabase.co';
  const SUPABASE_PUBLISHABLE_KEY='sb_publishable_3ibkYwM0fFdHgKdGFIN5cQ_BT_WudUW';

  if(!window.supabase||typeof window.supabase.createClient!=='function'){
    throw new Error('Supabase client library is not available.');
  }

  if(!window.FootballPAClient){
    window.FootballPAClient=window.supabase.createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY);
  }

  if(!window.FootballPAConfig){
    window.FootballPAConfig=Object.freeze({
      supabaseUrl:SUPABASE_URL
    });
  }
})();
